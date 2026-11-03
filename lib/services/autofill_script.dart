import 'dart:convert';

/// 生成注入到绿联云登录页的自动填充脚本。
///
/// 脚本会在当前页面寻找可见的密码框与账号框，使用原生 setter 赋值并派发
/// input/change 事件（兼容 React、Vue、Angular 的受控输入），随后按需点击登录按钮。
/// 执行结果通过 `UGShellBridge` 通道回传给 Flutter。
String buildAutoFillScript({
  required String account,
  required String password,
  required bool submit,
}) {
  final payload = jsonEncode({
    'account': account,
    'password': password,
    'submit': submit,
  });

  return '''
(function () {
  var payload = $payload;
  function post(status, extra) {
    try {
      if (window.UGShellBridge && window.UGShellBridge.postMessage) {
        var message = { type: 'autofill', status: status };
        if (extra) {
          for (var key in extra) { message[key] = extra[key]; }
        }
        window.UGShellBridge.postMessage(JSON.stringify(message));
      }
    } catch (error) {}
  }
  function visible(el) {
    if (!el) return false;
    var rect = el.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) return false;
    var style = window.getComputedStyle(el);
    return style.display !== 'none' && style.visibility !== 'hidden' && parseFloat(style.opacity) > 0.05;
  }
  function nativeSet(el, value) {
    try {
      var proto = Object.getPrototypeOf(el);
      var desc = Object.getOwnPropertyDescriptor(proto, 'value');
      if (desc && desc.set) {
        desc.set.call(el, value);
      } else {
        el.value = value;
      }
    } catch (error) {
      el.value = value;
    }
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    el.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true, key: 'a' }));
  }
  function buttonText(el) {
    var text = el.innerText || el.textContent || el.value || el.getAttribute('aria-label') || '';
    return String(text).replace(/\\s+/g, '').toLowerCase();
  }
  var passwordFields = Array.prototype.slice.call(document.querySelectorAll('input[type="password"]')).filter(visible);
  if (!passwordFields.length) { post('no_form'); return; }
  var passwordField = passwordFields[0];
  if (passwordField.value) { post('already_filled'); return; }

  var allInputs = Array.prototype.slice.call(document.querySelectorAll('input')).filter(function (el) {
    if (el === passwordField || !visible(el)) return false;
    var type = (el.getAttribute('type') || 'text').toLowerCase();
    var ignored = ['hidden', 'checkbox', 'radio', 'submit', 'button', 'file', 'image', 'range', 'color', 'date', 'datetime-local', 'month', 'week', 'time', 'number'];
    if (ignored.indexOf(type) >= 0) return false;
    return type === 'text' || type === 'email' || type === 'tel' || type === 'search';
  });
  if (!allInputs.length) { post('no_user_field'); return; }

  var hints = /user|account|login|email|mail|phone|mobile|账号|帐号|用户|邮箱|手机/;
  var userField = null;
  for (var i = 0; i < allInputs.length; i++) {
    var el = allInputs[i];
    var hint = [el.name, el.id, el.getAttribute('autocomplete'), el.placeholder, el.getAttribute('aria-label')].join(' ').toLowerCase();
    if (hints.test(hint)) { userField = el; break; }
  }
  if (!userField) {
    for (var j = 0; j < allInputs.length; j++) {
      if (passwordField.compareDocumentPosition(allInputs[j]) & 2) { userField = allInputs[j]; }
    }
  }
  if (!userField) { userField = allInputs[0]; }

  nativeSet(userField, payload.account);
  nativeSet(passwordField, payload.password);
  post('filled');

  if (!payload.submit) return;
  setTimeout(function () {
    try {
      var buttons = Array.prototype.slice.call(document.querySelectorAll('button, [role="button"], input[type="submit"], .login-btn, .btn-login, .sign-in-btn')).filter(visible);
      var target = null;
      for (var k = 0; k < buttons.length; k++) {
        var text = buttonText(buttons[k]);
        if (text === '登录' || text === '登入' || text === '立即登录' || text === 'login' || text === 'signin' || text === 'sign in' || text === '登录/login') {
          target = buttons[k];
          break;
        }
      }
      if (!target) {
        for (var m = 0; m < buttons.length; m++) {
          var shortText = buttonText(buttons[m]);
          if (shortText.indexOf('登录') >= 0 && shortText.length <= 10) { target = buttons[m]; break; }
        }
      }
      if (!target) {
        var submits = Array.prototype.slice.call(document.querySelectorAll('button[type="submit"], input[type="submit"]')).filter(visible);
        if (submits.length) { target = submits[0]; }
      }
      if (target) {
        target.click();
        post('submitted');
      } else {
        ['keydown', 'keypress', 'keyup'].forEach(function (type) {
          passwordField.dispatchEvent(new KeyboardEvent(type, { bubbles: true, key: 'Enter', code: 'Enter', keyCode: 13, which: 13 }));
        });
        post('submitted_enter');
      }
    } catch (error) { post('submit_error'); }
  }, 320);
})();
''';
}
