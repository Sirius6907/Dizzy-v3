import 'package:flutter/material.dart';

import '../../settings/settings_page.dart';

class WatchEmptySources extends StatefulWidget {
  const WatchEmptySources({super.key});

  @override
  State<WatchEmptySources> createState() =>
      WatchEmptySourcesState();
}

class WatchEmptySourcesState extends State<WatchEmptySources>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );
    _scaleAnim = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOutBack),
      ),
    );
    // Run the entrance once. A perpetual pulse kept this whole state ticking.
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Static card content — identical on every platform.
    final cardContent = Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xF0141419),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF7C5CFC).withValues(alpha: 0.1),
              border: Border.all(
                color: const Color(0xFF7C5CFC).withValues(alpha: 0.3),
              ),
            ),
            child: const Icon(
              Icons.radar_rounded,
              color: Color(0xFF7C5CFC),
              size: 40,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No sources found',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: const Text(
              'No streams found. Install more addons from Settings or try another title.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF9B9BA5),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 32),
          MouseRegion(
            onEnter: (_) => setState(() => _isHovering = true),
            onExit: (_) => setState(() => _isHovering = false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C5CFC), Color(0xFF5CFCB6)],
                  ),
                  boxShadow: _isHovering
                      ? [
                          BoxShadow(
                            color: const Color(
                              0xFF7C5CFC,
                            ).withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [],
                ),
                child: AnimatedScale(
                  scale: _isHovering ? 1.05 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.extension_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Install Addons',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // The glass card — blur is static, not animated
    final glassCard = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: cardContent,
    );

    // Only the initial fade/scale is animated (runs once, then stops)
    return AnimatedBuilder(
      animation: _fadeAnim,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnim.value.clamp(0.0, 1.0),
          child: Transform.scale(scale: _scaleAnim.value, child: child),
        );
      },
      child: glassCard,
    );
  }
}
