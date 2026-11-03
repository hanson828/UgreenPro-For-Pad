/// 让绿联云网页端在「当前文件夹」里弹出上传。
///
/// 背景：UGOS 的文件管理只在**右键点击列表空白处**的菜单里给出「上传到 / 上传文件」，
/// 触屏没有右键，所以平板上根本没有入口。这里的脚本用合成事件走同一条路：
/// 合成 contextmenu 打开菜单 → 悬停展开子菜单 → 点「上传文件」。
/// 之后网页自己会显示「重命名文件处理」对话框并创建 `<input type="file">`，
/// 由原生文件选择器接管，选完文件就由网页走它原来的上传逻辑，服务器端行为完全一致。
const String _uploadScript = r"""
(function () {
  if (window.__ugUploading) {
    return;
  }
  window.__ugUploading = true;

  var report = function (status, reason) {
    window.__ugUploading = false;
    try {
      UGShellBridge.postMessage(JSON.stringify({
        type: 'upload',
        status: status,
        reason: reason || ''
      }));
    } catch (e) {}
  };

  var sleep = function (ms) {
    return new Promise(function (resolve) { setTimeout(resolve, ms); });
  };

  // 顶层页面 + 所有同源子 frame（文件管理是一个 iframe）
  function allDocs() {
    var docs = [document];
    var walk = function (root) {
      var frames;
      try { frames = root.querySelectorAll('iframe'); } catch (e) { return; }
      for (var i = 0; i < frames.length; i++) {
        var inner = null;
        try { inner = frames[i].contentDocument; } catch (e) { inner = null; }
        if (inner) {
          docs.push(inner);
          walk(inner);
        }
      }
    };
    walk(document);
    return docs;
  }

  var visible = function (el) {
    var r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  };

  function findLeaf(match) {
    var docs = allDocs();
    for (var d = 0; d < docs.length; d++) {
      var list = docs[d].querySelectorAll('*');
      for (var i = 0; i < list.length; i++) {
        var el = list[i];
        if (el.children.length) { continue; }
        var text = (el.textContent || '').trim();
        if (!text || text.length > 24) { continue; }
        if (!match(text)) { continue; }
        if (!visible(el)) { continue; }
        return el;
      }
    }
    return null;
  }

  async function waitFor(find, timeoutMs) {
    var end = Date.now() + timeoutMs;
    while (Date.now() < end) {
      var found = find();
      if (found) { return found; }
      await sleep(70);
    }
    return null;
  }

  function fire(target, type, x, y, button, buttons) {
    try {
      target.dispatchEvent(new MouseEvent(type, {
        bubbles: type !== 'mouseenter' && type !== 'pointerenter',
        cancelable: true,
        composed: true,
        clientX: x,
        clientY: y,
        screenX: x,
        screenY: y,
        button: button,
        buttons: buttons,
        which: button === 2 ? 3 : 1
      }));
    } catch (e) {}
  }

  function clickEl(el) {
    var r = el.getBoundingClientRect();
    var x = r.left + r.width / 2;
    var y = r.top + r.height / 2;
    fire(el, 'mousedown', x, y, 0, 1);
    fire(el, 'mouseup', x, y, 0, 0);
    fire(el, 'click', x, y, 0, 0);
    try { el.click(); } catch (e) {}
  }

  (async function () {
    // 1) 文件列表容器（只有文件管理窗口里有）
    var host = null;
    var hostDoc = null;
    var selectors = ['.resources-list', '.main-body__primary', '.file-manage-main'];
    var docs = allDocs();
    for (var d = 0; d < docs.length && !host; d++) {
      for (var s = 0; s < selectors.length; s++) {
        var cand = docs[d].querySelector(selectors[s]);
        if (cand && cand.getBoundingClientRect().height > 150) {
          host = cand;
          hostDoc = docs[d];
          break;
        }
      }
    }
    if (!host) {
      report('err', 'no_list');
      return;
    }

    // 2) 找一块真正的空白（该点下面不是文件项），否则右键菜单是「针对某个文件」的
    var rect = host.getBoundingClientRect();
    var isBlank = function (el) {
      var node = el;
      for (var i = 0; i < 3 && node; i++) {
        var cls = (node.className || '').toString();
        if (/file-item|virtual-item|item-|name-box|icon/.test(cls)) { return false; }
        node = node.parentElement;
      }
      return true;
    };
    var pointX = null;
    var pointY = null;
    var pointEl = null;
    var fx = [0.9, 0.75, 0.6, 0.45, 0.3];
    var fy = [0.95, 0.88, 0.8];
    for (var yi = 0; yi < fy.length && pointX === null; yi++) {
      for (var xi = 0; xi < fx.length; xi++) {
        var x = rect.left + rect.width * fx[xi];
        var y = rect.top + rect.height * fy[yi];
        var under = hostDoc.elementFromPoint(x, y);
        if (under && isBlank(under)) {
          pointX = x;
          pointY = y;
          pointEl = under;
          break;
        }
      }
    }
    if (pointX === null) {
      pointEl = host;
      pointX = rect.left + rect.width * 0.9;
      pointY = rect.top + rect.height * 0.95;
    }

    // 3) 合成右键 → 菜单
    fire(pointEl, 'mousedown', pointX, pointY, 2, 2);
    fire(pointEl, 'mouseup', pointX, pointY, 2, 0);
    fire(pointEl, 'contextmenu', pointX, pointY, 2, 2);

    var parentLeaf = await waitFor(function () {
      return findLeaf(function (t) { return t.indexOf('上传到') === 0; });
    }, 1600);
    if (!parentLeaf) {
      report('err', 'no_menu');
      return;
    }

    // 4) 悬停展开子菜单
    var parentItem = parentLeaf.closest('.context-item') || parentLeaf.parentElement || parentLeaf;
    var pr = parentItem.getBoundingClientRect();
    var hovers = ['pointerover', 'mouseover', 'pointerenter', 'mouseenter', 'mousemove'];
    for (var h = 0; h < hovers.length; h++) {
      fire(parentItem, hovers[h], pr.left + pr.width / 2, pr.top + pr.height / 2, 0, 0);
    }

    var fileLeaf = await waitFor(function () {
      return findLeaf(function (t) { return t === '上传文件'; });
    }, 1600);
    if (!fileLeaf) {
      report('err', 'no_submenu');
      return;
    }

    // 5) 点「上传文件」：网页会弹「重命名文件处理」，确定后自己创建 input[type=file]
    clickEl(fileLeaf.closest('.context-item') || fileLeaf);
    report('ok', '');
  })();
})();
""";

/// 生成注入用的脚本。
String buildUploadScript() => _uploadScript;
