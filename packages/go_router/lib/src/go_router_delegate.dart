// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'custom_transition_page.dart';
import 'go_route_information_parser.dart';
import 'go_route_match.dart';
import 'go_router_cupertino.dart';
import 'go_router_error_page.dart';
import 'go_router_material.dart';
import 'go_router_state.dart';
import 'logging.dart';
import 'route_data.dart';
import 'typedefs.dart';

/// GoRouter implementation of the RouterDelegate base class.
class GoRouterDelegate extends RouterDelegate<List<GoRouteMatch>>
    with PopNavigatorRouterDelegateMixin<List<GoRouteMatch>>, ChangeNotifier {
  /// Constructor for GoRouter's implementation of the
  /// RouterDelegate base class.
  GoRouterDelegate(
    this._parser, {
    required this.builderWithNav,
    required this.errorPageBuilder,
    required this.errorBuilder,
    required this.observers,
    required this.routerNeglect,
    this.restorationScopeId,
  });

  // TODO(chunhtai): remove this once namedLocation is removed from go_router.
  final GoRouteInformationParser _parser;

  /// Builder function for a go router with Navigator.
  final GoRouterBuilderWithNav builderWithNav;

  /// Error page builder for the go router delegate.
  final GoRouterPageBuilder? errorPageBuilder;

  /// Error widget builder for the go router delegate.
  final GoRouterWidgetBuilder? errorBuilder;

  /// NavigatorObserver used to receive change notifications when
  /// navigation changes.
  final List<NavigatorObserver> observers;

  /// Set to true to disable creating history entries on the web.
  final bool routerNeglect;

  /// Restoration ID to save and restore the state of the navigator, including
  /// its history.
  final String? restorationScopeId;

  final GlobalKey<NavigatorState> _key = GlobalKey<NavigatorState>();
  List<GoRouteMatch> _matches = const <GoRouteMatch>[];

  /// Push the given location onto the page stack
  void push(GoRouteMatch match) {
    _matches.add(match);
    notifyListeners();
  }

  /// Pop the top page off the GoRouter's page stack.
  void pop() {
    _matches.remove(_matches.last);
    assert(_matches.isNotEmpty,
        'have popped the last page off of the stack; there are no pages left to show');
    notifyListeners();
  }

  /// For internal use; visible for testing only.
  @visibleForTesting
  List<GoRouteMatch> get matches => _matches;

  /// For use by the Router architecture as part of the RouterDelegate.
  @override
  GlobalKey<NavigatorState> get navigatorKey => _key;

  /// For use by the Router architecture as part of the RouterDelegate.
  @override
  List<GoRouteMatch> get currentConfiguration => _matches;

  /// For use by the Router architecture as part of the RouterDelegate.
  @override
  Widget build(BuildContext context) => _builder(context, _matches);

  /// For use by the Router architecture as part of the RouterDelegate.
  @override
  Future<void> setNewRoutePath(List<GoRouteMatch> configuration) {
    _matches = configuration;
    // Use [SynchronousFuture] so that the initial url is processed
    // synchronously and remove unwanted initial animations on deep-linking
    return SynchronousFuture<void>(null);
  }

  Widget _builder(BuildContext context, Iterable<GoRouteMatch> matches) {
    List<Page<dynamic>>? pages;
    Exception? error;
    final String location = matches.last.fullUriString;
    try {
      // build the stack of pages
      if (routerNeglect) {
        Router.neglect(
          context,
          () => pages = getPages(context, matches.toList()).toList(),
        );
      } else {
        pages = getPages(context, matches.toList()).toList();
      }

      // note that we need to catch it this way to get all the info, e.g. the
      // file/line info for an error in an inline function impl, e.g. an inline
      // `redirect` impl
      // ignore: avoid_catches_without_on_clauses
    } catch (err, stack) {
      assert(() {
        log.severe('Exception during GoRouter navigation', err, stack);
        return true;
      }());

      // if there's an error, show an error page
      error = err is Exception ? err : Exception(err);
      final Uri uri = Uri.parse(location);
      pages = <Page<dynamic>>[
        _errorPageBuilder(
          context,
          GoRouterState(
            _parser,
            location: location,
            subloc: uri.path,
            name: null,
            queryParams: uri.queryParameters,
            error: error,
          ),
        ),
      ];
    }

    // we should've set pages to something by now
    assert(pages != null);

    // pass either the match error or the build error along to the navigator
    // builder, preferring the match error
    if (matches.length == 1 && matches.first.error != null) {
      error = matches.first.error;
    }

    // wrap the returned Navigator to enable GoRouter.of(context).go()
    final Uri uri = Uri.parse(location);
    return builderWithNav(
      context,
      GoRouterState(
        _parser,
        location: location,
        name: null, // no name available at the top level
        // trim the query params off the subloc to match route.redirect
        subloc: uri.path,
        // pass along the query params 'cuz that's all we have right now
        queryParams: uri.queryParameters,
        // pass along the error, if there is one
        error: error,
      ),
      Navigator(
        restorationScopeId: restorationScopeId,
        key: _key, // needed to enable Android system Back button
        pages: pages!,
        observers: observers,
        onPopPage: (Route<dynamic> route, dynamic result) {
          if (!route.didPop(result)) {
            return false;
          }
          pop();
          return true;
        },
      ),
    );
  }

  /// Get the stack of sub-routes that matches the location and turn it into a
  /// stack of pages, e.g.
  /// routes: <GoRoute>[
  ///   /
  ///     family/:fid
  ///       person/:pid
  ///   /login
  /// ]
  ///
  /// loc: /
  /// pages: [ HomePage()]
  ///
  /// loc: /login
  /// pages: [ LoginPage() ]
  ///
  /// loc: /family/f2
  /// pages: [ HomePage(), FamilyPage(f2) ]
  ///
  /// loc: /family/f2/person/p1
  /// pages: [ HomePage(), FamilyPage(f2), PersonPage(f2, p1) ]
  @visibleForTesting
  Iterable<Page<dynamic>> getPages(
    BuildContext context,
    List<GoRouteMatch> matches,
  ) sync* {
    assert(matches.isNotEmpty);

    Map<String, String> params = <String, String>{};
    for (final GoRouteMatch match in matches) {
      // merge new params to keep params from previously matched paths, e.g.
      // /family/:fid/person/:pid provides fid and pid to person/:pid
      params = <String, String>{...params, ...match.decodedParams};

      // get a page from the builder and associate it with a sub-location
      final GoRouterState state = GoRouterState(
        _parser,
        location: match.fullUriString,
        subloc: match.subloc,
        name: match.route.name,
        path: match.route.path,
        fullpath: match.fullpath,
        params: params,
        error: match.error,
        queryParams: match.queryParams,
        extra: match.extra,
        pageKey: match.pageKey, // push() remaps the page key for uniqueness
      );
      if (match.error != null) {
        yield _errorPageBuilder(context, state);
        break;
      }

      final GoRouterPageBuilder? pageBuilder = match.route.pageBuilder;
      Page<dynamic>? page;
      if (pageBuilder != null) {
        page = pageBuilder(context, state);
        if (page is NoOpPage) {
          page = null;
        }
      }

      yield page ?? _pageBuilder(context, state, match.route.builder);
    }
  }

  Page<void> Function({
    required LocalKey key,
    required String? name,
    required Object? arguments,
    required String restorationId,
    required Widget child,
  })? _pageBuilderForAppType;

  Widget Function(
    BuildContext context,
    GoRouterState state,
  )? _errorBuilderForAppType;

  void _cacheAppType(BuildContext context) {
    // cache app type-specific page and error builders
    if (_pageBuilderForAppType == null) {
      assert(_errorBuilderForAppType == null);

      // can be null during testing
      final Element? elem = context is Element ? context : null;

      if (elem != null && isMaterialApp(elem)) {
        assert(() {
          log.info('MaterialApp found');
          return true;
        }());
        _pageBuilderForAppType = pageBuilderForMaterialApp;
        _errorBuilderForAppType = (BuildContext c, GoRouterState s) =>
            GoRouterMaterialErrorScreen(s.error);
      } else if (elem != null && isCupertinoApp(elem)) {
        assert(() {
          log.info('CupertinoApp found');
          return true;
        }());
        _pageBuilderForAppType = pageBuilderForCupertinoApp;
        _errorBuilderForAppType = (BuildContext c, GoRouterState s) =>
            GoRouterCupertinoErrorScreen(s.error);
      } else {
        assert(() {
          log.info('WidgetsApp found');
          return true;
        }());
        _pageBuilderForAppType = pageBuilderForWidgetApp;
        _errorBuilderForAppType =
            (BuildContext c, GoRouterState s) => GoRouterErrorScreen(s.error);
      }
    }

    assert(_pageBuilderForAppType != null);
    assert(_errorBuilderForAppType != null);
  }

  // builds the page based on app type, i.e. MaterialApp vs. CupertinoApp
  Page<dynamic> _pageBuilder(
    BuildContext context,
    GoRouterState state,
    GoRouterWidgetBuilder builder,
  ) {
    // build the page based on app type
    _cacheAppType(context);
    return _pageBuilderForAppType!(
      key: state.pageKey,
      name: state.name ?? state.fullpath,
      arguments: <String, String>{...state.params, ...state.queryParams},
      restorationId: state.pageKey.value,
      child: builder(context, state),
    );
  }

  /// Builds a page without any transitions.
  Page<void> pageBuilderForWidgetApp({
    required LocalKey key,
    required String? name,
    required Object? arguments,
    required String restorationId,
    required Widget child,
  }) =>
      NoTransitionPage<void>(
        name: name,
        arguments: arguments,
        key: key,
        restorationId: restorationId,
        child: child,
      );

  Page<void> _errorPageBuilder(
    BuildContext context,
    GoRouterState state,
  ) {
    // if the error page builder is provided, use that; otherwise, if the error
    // builder is provided, wrap that in an app-specific page, e.g.
    // MaterialPage; finally, if nothing is provided, use a default error page
    // wrapped in the app-specific page, e.g.
    // MaterialPage(GoRouterMaterialErrorPage(...))
    _cacheAppType(context);
    return errorPageBuilder != null
        ? errorPageBuilder!(context, state)
        : _pageBuilder(
            context,
            state,
            errorBuilder ?? _errorBuilderForAppType!,
          );
  }
}
