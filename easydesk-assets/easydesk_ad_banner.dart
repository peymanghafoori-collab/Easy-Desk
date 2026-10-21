// EasyDesk: dynamic ad banner for the home page.
//
// The banners are read from a small JSON file at a fixed address. Titles, links,
// images and the number of banners all live in that file, so they can be changed
// without rebuilding or reinstalling the app. Any error (no network, bad JSON) just
// hides the banner; it must never get in the way of the app itself.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const String _kAdsUrl = '__ADS_URL__';
const int _kMaxBanners = 10;
const double _kBannerHeight = 96;

class _AdBanner {
  final String text;
  final String image;
  final String link;
  const _AdBanner(this.text, this.image, this.link);
}

bool _isWebUrl(String s) {
  final u = Uri.tryParse(s);
  return u != null &&
      (u.scheme == 'https' || u.scheme == 'http') &&
      u.host.isNotEmpty;
}

int _intOr(dynamic v, int def, int min, int max) {
  final n = v is num ? v.toInt() : int.tryParse(v?.toString() ?? '');
  if (n == null) return def;
  if (n < min) return min;
  if (n > max) return max;
  return n;
}

class EasyDeskAdBanner extends StatefulWidget {
  const EasyDeskAdBanner({Key? key}) : super(key: key);

  @override
  State<EasyDeskAdBanner> createState() => _EasyDeskAdBannerState();
}

class _EasyDeskAdBannerState extends State<EasyDeskAdBanner> {
  List<_AdBanner> _banners = const [];
  int _index = 0;
  int _rotateSeconds = 8;
  int _refreshMinutes = 30;
  Timer? _rotateTimer;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _rotateTimer?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final resp = await http
          .get(Uri.parse(_kAdsUrl))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        _apply(jsonDecode(utf8.decode(resp.bodyBytes)));
      }
    } catch (_) {
      // keep showing whatever was loaded before
    }
    _scheduleRefresh();
  }

  void _apply(dynamic data) {
    if (!mounted || data is! Map) return;
    final list = <_AdBanner>[];
    if (data['enabled'] != false && data['banners'] is List) {
      for (final b in data['banners']) {
        if (b is! Map) continue;
        final text = (b['text'] ?? '').toString().trim();
        var image = (b['image'] ?? '').toString().trim();
        var link = (b['link'] ?? '').toString().trim();
        if (!_isWebUrl(image)) image = '';
        if (!_isWebUrl(link)) link = '';
        if (text.isEmpty && image.isEmpty) continue;
        list.add(_AdBanner(text, image, link));
        if (list.length >= _kMaxBanners) break;
      }
    }
    setState(() {
      _banners = list;
      if (_index >= list.length) _index = 0;
      _rotateSeconds = _intOr(data['rotate_seconds'], 8, 3, 120);
      _refreshMinutes = _intOr(data['refresh_minutes'], 30, 1, 1440);
    });
    _scheduleRotate();
  }

  void _scheduleRotate() {
    _rotateTimer?.cancel();
    if (_banners.length < 2) return;
    _rotateTimer = Timer.periodic(Duration(seconds: _rotateSeconds), (_) {
      if (!mounted || _banners.isEmpty) return;
      setState(() => _index = (_index + 1) % _banners.length);
    });
  }

  void _scheduleRefresh() {
    if (!mounted) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(Duration(minutes: _refreshMinutes), _load);
  }

  Widget _textCard(_AdBanner b) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF3949AB), Color(0xFF42A5A0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Text(
        b.text,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _imageCard(_AdBanner b) {
    return Image.network(
      b.image,
      fit: BoxFit.cover,
      width: double.infinity,
      height: _kBannerHeight,
      errorBuilder: (_, __, ___) => _textCard(b),
      loadingBuilder: (context, child, progress) {
        if (progress != null) return _textCard(b);
        if (b.text.isEmpty) return child;
        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  b.text,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _card(_AdBanner b) {
    return SizedBox(
      key: ValueKey<String>('$_index|${b.text}|${b.image}'),
      height: _kBannerHeight,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: b.image.isEmpty ? _textCard(b) : _imageCard(b),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_banners.isEmpty) return const SizedBox.shrink();
    final b = _banners[_index];
    final clickable = b.link.isNotEmpty;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 6, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MouseRegion(
            cursor: clickable ? SystemMouseCursors.click : MouseCursor.defer,
            child: GestureDetector(
              onTap: clickable ? () => launchUrl(Uri.parse(b.link)) : null,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _card(b),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Ad · تبلیغ',
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
              if (_banners.length > 1) const SizedBox(width: 8),
              if (_banners.length > 1)
                for (var i = 0; i < _banners.length; i++)
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _index
                          ? const Color(0xFF3949AB)
                          : Colors.grey.withOpacity(0.4),
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}
