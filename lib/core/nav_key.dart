import 'package:flutter/widgets.dart';

/// Global navigator key (v1.2.0-P3: guest auto-open needs context-free nav).
/// Lives here (not main.dart) so services can import it without cycles.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
