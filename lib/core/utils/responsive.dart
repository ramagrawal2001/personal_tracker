import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// Breakpoints for responsive design
class AppBreakpoints {
  static const double mobile = 480;
  static const double tablet = 600;
  static const double desktop = 900;
  static const double largeDesktop = 1200;
}

/// Mixin/helper for responsive UI logic
mixin ResponsiveMixin<T extends StatefulWidget> on State<T> {
  bool get isMobile => MediaQuery.of(context).size.width < AppBreakpoints.tablet;
  bool get isTablet => MediaQuery.of(context).size.width >= AppBreakpoints.tablet && MediaQuery.of(context).size.width < AppBreakpoints.desktop;
  bool get isDesktop => MediaQuery.of(context).size.width >= AppBreakpoints.desktop;
  bool get isLargeScreen => MediaQuery.of(context).size.width >= AppBreakpoints.tablet;
  bool get isLandscape => MediaQuery.of(context).orientation == Orientation.landscape;
  bool get isCompact => isMobile && isLandscape;
}

extension ResponsiveContext on BuildContext {
  bool get isMobile => MediaQuery.of(this).size.width < AppBreakpoints.tablet;
  bool get isTablet => MediaQuery.of(this).size.width >= AppBreakpoints.tablet && MediaQuery.of(this).size.width < AppBreakpoints.desktop;
  bool get isDesktop => MediaQuery.of(this).size.width >= AppBreakpoints.desktop;
  bool get isLargeScreen => MediaQuery.of(this).size.width >= AppBreakpoints.tablet;
  bool get isLandscape => MediaQuery.of(this).orientation == Orientation.landscape;
  bool get isCompact => isMobile && isLandscape;

  double get screenWidth => MediaQuery.of(this).size.width;
  double get screenHeight => MediaQuery.of(this).size.height;
  double get safePadding => MediaQuery.of(this).padding.top;
  double get safeBottomPadding => MediaQuery.of(this).padding.bottom;
  double get viewInsetsBottom => MediaQuery.of(this).viewInsets.bottom;

  double responsivePadding({double mobile = 16, double tablet = 24, double desktop = 32}) {
    final width = screenWidth;
    if (width >= AppBreakpoints.desktop) return desktop;
    if (width >= AppBreakpoints.tablet) return tablet;
    return mobile;
  }

  double responsiveHorizontalPadding({double mobile = 16, double tablet = 32, double desktop = 48}) {
    return responsivePadding(mobile: mobile, tablet: tablet, desktop: desktop);
  }

  double responsiveCardPadding({double mobile = 12, double tablet = 16, double desktop = 20}) {
    return responsivePadding(mobile: mobile, tablet: tablet, desktop: desktop);
  }

  int responsiveCrossAxisCount({int mobile = 1, int tablet = 2, int desktop = 3, double maxExtent = 400}) {
    final width = screenWidth;
    if (width >= AppBreakpoints.desktop) return desktop;
    if (width >= AppBreakpoints.tablet) return tablet;
    return mobile;
  }

  double responsiveFontSize({double mobile = 14, double tablet = 16, double desktop = 18}) {
    final scale = MediaQuery.textScalerOf(this).scale(1.0);
    final width = screenWidth;
    double base;
    if (width >= AppBreakpoints.desktop) {
      base = desktop;
    } else if (width >= AppBreakpoints.tablet) {
      base = tablet;
    } else {
      base = mobile;
    }
    return base * scale;
  }

  double responsiveIconSize({double mobile = 20, double tablet = 24, double desktop = 28}) {
    final width = screenWidth;
    if (width >= AppBreakpoints.desktop) return desktop;
    if (width >= AppBreakpoints.tablet) return tablet;
    return mobile;
  }

  bool get shouldUseNavigationRail => isTablet || isDesktop;
  bool get shouldUseTwoColumnLayout => isTablet || isDesktop;
  bool get shouldShowMasterDetail => isTablet || isDesktop;
  bool get shouldUsePopover => isTablet || isDesktop;
}

/// Adaptive modal helper
class AdaptiveModal {
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = true,
    bool useRootNavigator = true,
    Color? barrierColor,
    bool? usePopover,
    Color? backgroundColor,
    ShapeBorder? shape,
  }) {
    final usePopoverModal = usePopover ?? context.shouldUsePopover;
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;

    if (usePopoverModal && isIOS) {
      return showDialog<T>(
        context: context,
        useRootNavigator: useRootNavigator,
        barrierColor: barrierColor ?? Colors.black54,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.all(24),
          clipBehavior: Clip.antiAlias,
          shape: shape ?? RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.9,
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            child: builder(ctx),
          ),
        ),
      );
    }

    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      useRootNavigator: useRootNavigator,
      backgroundColor: backgroundColor ?? Colors.transparent,
      shape: shape,
      builder: builder,
    );
  }
}

/// Adaptive scaffold that switches between NavigationRail and BottomNavigationBar
class AdaptiveScaffold extends StatefulWidget {
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final List<NavigationRailDestination> railDestinations;
  final List<BottomNavigationBarItem> barItems;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget? drawer;
  final Widget? endDrawer;
  final Color? backgroundColor;
  final bool extendBody;
  final bool extendBodyBehindAppBar;

  const AdaptiveScaffold({
    super.key,
    required this.body,
    required this.railDestinations,
    required this.barItems,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.appBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.drawer,
    this.endDrawer,
    this.backgroundColor,
    this.extendBody = false,
    this.extendBodyBehindAppBar = false,
  });

  @override
  State<AdaptiveScaffold> createState() => _AdaptiveScaffoldState();
}

class _AdaptiveScaffoldState extends State<AdaptiveScaffold> {
  @override
  Widget build(BuildContext context) {
    final isLargeScreen = context.isLargeScreen;

    if (isLargeScreen) {
      return Scaffold(
        backgroundColor: widget.backgroundColor,
        appBar: widget.appBar,
        drawer: widget.drawer,
        endDrawer: widget.endDrawer,
        floatingActionButton: widget.floatingActionButton,
        floatingActionButtonLocation: widget.floatingActionButtonLocation,
        extendBody: widget.extendBody,
        extendBodyBehindAppBar: widget.extendBodyBehindAppBar,
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: widget.selectedIndex,
              onDestinationSelected: widget.onDestinationSelected,
              labelType: NavigationRailLabelType.all,
              destinations: widget.railDestinations,
              extended: context.screenWidth >= AppBreakpoints.desktop,
              minExtendedWidth: 200,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              indicatorColor: Theme.of(context).colorScheme.primaryContainer,
              selectedIconTheme: IconThemeData(color: Theme.of(context).colorScheme.primary),
              unselectedIconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurfaceVariant),
              selectedLabelTextStyle: TextStyle(color: Theme.of(context).colorScheme.primary),
              unselectedLabelTextStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(child: widget.body),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: widget.backgroundColor,
      appBar: widget.appBar,
      drawer: widget.drawer,
      endDrawer: widget.endDrawer,
      floatingActionButton: widget.floatingActionButton,
      floatingActionButtonLocation: widget.floatingActionButtonLocation,
      extendBody: widget.extendBody,
      extendBodyBehindAppBar: widget.extendBodyBehindAppBar,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: widget.selectedIndex,
        onTap: widget.onDestinationSelected,
        items: widget.barItems,
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: true,
        showUnselectedLabels: true,
      ),
      body: widget.body,
    );
  }
}

/// Responsive grid delegate using SliverGridDelegateWithMaxCrossAxisExtent
class ResponsiveGridDelegate extends SliverGridDelegateWithMaxCrossAxisExtent {
  const ResponsiveGridDelegate({
    required super.maxCrossAxisExtent,
    super.mainAxisSpacing = 10,
    super.crossAxisSpacing = 10,
    super.childAspectRatio = 1.0,
  });
}

/// Responsive value helper
T responsiveValue<T>(BuildContext context, {
  required T mobile,
  T? tablet,
  T? desktop,
}) {
  final width = MediaQuery.of(context).size.width;
  if (width >= AppBreakpoints.desktop && desktop != null) return desktop;
  if (width >= AppBreakpoints.tablet && tablet != null) return tablet;
  return mobile;
}