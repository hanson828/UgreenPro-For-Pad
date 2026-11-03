import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 绿联云官方图标，右下角带浏览器角标。
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 48, this.showGlow = true});

  final double size;
  final bool showGlow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.24),
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: AppColors.brandInk.withValues(alpha: 0.3),
                  blurRadius: size * 0.34,
                  offset: Offset(0, size * 0.14),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.24),
        child: Image.asset(
          'assets/brand/ugreen_cloud_browser.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

/// 品牌文字组合：图形标识 + 产品名。
class BrandTitle extends StatelessWidget {
  const BrandTitle({
    super.key,
    this.light = false,
    this.markSize = 46,
    this.title = '绿联云',
    this.subtitle = '平板网页端',
  });

  final bool light;
  final double markSize;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: markSize),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: light ? Colors.white : AppColors.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11.5,
                letterSpacing: 0.6,
                color: light ? Colors.white70 : AppColors.muted,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
