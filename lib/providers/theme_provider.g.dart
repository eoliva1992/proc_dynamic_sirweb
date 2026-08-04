// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'theme_provider.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$ThemeStore on _ThemeStore, Store {
  Computed<bool>? _$isDarkComputed;

  @override
  bool get isDark => (_$isDarkComputed ??= Computed<bool>(
    () => super.isDark,
    name: '_ThemeStore.isDark',
  )).value;

  late final _$themeModeAtom = Atom(
    name: '_ThemeStore.themeMode',
    context: context,
  );

  @override
  ThemeMode get themeMode {
    _$themeModeAtom.reportRead();
    return super.themeMode;
  }

  @override
  set themeMode(ThemeMode value) {
    _$themeModeAtom.reportWrite(value, super.themeMode, () {
      super.themeMode = value;
    });
  }

  late final _$toggleAsyncAction = AsyncAction(
    '_ThemeStore.toggle',
    context: context,
  );

  @override
  Future<void> toggle() {
    return _$toggleAsyncAction.run(() => super.toggle());
  }

  @override
  String toString() {
    return '''
themeMode: ${themeMode},
isDark: ${isDark}
    ''';
  }
}
