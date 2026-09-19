// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:fiber_pylon/src/credential/credentials.dart' as _i940;
import 'package:fiber_pylon/src/sdk/clients/local/database/engine/database.dart'
    as _i63;
import 'package:fiber_pylon/src/storage/preferences_storage.dart' as _i425;
import 'package:fiber_pylon/src/storage/secure_storage.dart' as _i134;
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;

extension GetItInjectableX on _i174.GetIt {
  // initializes the registration of main-scope dependencies inside of GetIt
  Future<_i174.GetIt> init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) async {
    final gh = _i526.GetItHelper(this, environment, environmentFilter);
    await gh.singletonAsync<_i134.SecureStorage>(
      () => _i134.SecureStorage.initialize(),
      preResolve: true,
      dispose: (i) => i.dispose(),
    );
    await gh.singletonAsync<_i425.PreferencesStorage>(
      () => _i425.PreferencesStorage.initialize(),
      preResolve: true,
    );
    await gh.singletonAsync<_i940.Credentials>(
      () => _i940.Credentials.initialize(gh<_i134.SecureStorage>()),
      preResolve: true,
      dispose: (i) => i.dispose(),
    );
    await gh.singletonAsync<_i63.LocalDatabase>(
      () => _i63.LocalDatabase.initialize(gh<_i134.SecureStorage>()),
      preResolve: true,
      dispose: (i) => i.dispose(),
    );
    return this;
  }
}
