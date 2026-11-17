import 'dart:async';

import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'offline_banner.dart';

/// Phase 31 — Scaffold wrapper that adds a universal offline banner.
///
/// Listens to Connectivity changes automatically. The banner appears at
/// the top of the body when offline and slides away when reconnected.
/// All copy is Easy English.
class OfflineAwareScaffold extends StatefulWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final List<Widget> persistentFooterButtons;
  final Drawer? drawer;
  final Widget? endDrawer;
  final Color? backgroundColor;
  final bool resizeToAvoidBottomInset;
  final bool extendBodyBehindAppBar;
  final EdgeInsetsGeometry? padding;

  const OfflineAwareScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.persistentFooterButtons = const <Widget>[],
    this.drawer,
    this.endDrawer,
    this.backgroundColor,
    this.resizeToAvoidBottomInset = true,
    this.extendBodyBehindAppBar = false,
    this.padding,
  });

  @override
  State<OfflineAwareScaffold> createState() => _OfflineAwareScaffoldState();
}

class _OfflineAwareScaffoldState extends State<OfflineAwareScaffold> {
  bool _offline = false;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  @override
  void initState() {
    super.initState();
    // v1.3.4: a cold start while already offline used to assume "wifi" and
    // never show the banner until the radio state changed. Ask once up front,
    // then keep listening.
    _subscription = Connectivity().onConnectivityChanged.listen(_apply);
    Connectivity().checkConnectivity().then(_apply).catchError((Object _) {});
  }

  void _apply(List<ConnectivityResult> results) {
    final offline =
        results.isEmpty || results.any((r) => r == ConnectivityResult.none);
    if (mounted && offline != _offline) {
      setState(() => _offline = offline);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.appBar,
      extendBodyBehindAppBar: widget.extendBodyBehindAppBar,
      body: Stack(
        children: [
          Padding(
            padding: widget.padding ?? EdgeInsets.zero,
            child: widget.body,
          ),
          if (_offline) const DizzyOfflineBanner(isOffline: true),
        ],
      ),
      floatingActionButton: widget.floatingActionButton,
      floatingActionButtonLocation: widget.floatingActionButtonLocation,
      persistentFooterButtons: widget.persistentFooterButtons,
      drawer: widget.drawer,
      endDrawer: widget.endDrawer,
      backgroundColor: widget.backgroundColor,
      resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
    );
  }
}
