import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'offline_banner.dart';

/// Phase 31 — Scaffold wrapper that adds a universal offline banner.
///
/// Listens to Connectivity changes automatically. The banner appears at
/// the top of the body when offline and slides away when reconnected.
/// All copy is Easy English.
class OfflineAwareScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final List<Widget> persistentFooterButtons;
  final Drawer? drawer;
  final Widget? endDrawer;
  final Color? backgroundColor;
  final bool resizeToAvoidBottomInset;
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
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ConnectivityResult>>(
      stream: Connectivity().onConnectivityChanged,
      initialData: const [ConnectivityResult.wifi],
      builder: (context, snapshot) {
        final results = snapshot.data ?? const [ConnectivityResult.wifi];
        final isOffline = results.isEmpty ||
            results.any((r) => r == ConnectivityResult.none);
        return Scaffold(
          appBar: appBar,
          body: Stack(
            children: [
              Padding(
                padding: padding ?? EdgeInsets.zero,
                child: body,
              ),
              if (isOffline) const DizzyOfflineBanner(isOffline: true),
            ],
          ),
          floatingActionButton: floatingActionButton,
          floatingActionButtonLocation: floatingActionButtonLocation,
          persistentFooterButtons: persistentFooterButtons,
          drawer: drawer,
          endDrawer: endDrawer,
          backgroundColor: backgroundColor,
          resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        );
      },
    );
  }
}
