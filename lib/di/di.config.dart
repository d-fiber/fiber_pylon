// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:fiber_pylon/src/sdk/clients/local/database/engine/app.dart'
    as _i167;
import 'package:fiber_pylon/src/storage/secure_storage.dart' as _i134;
import 'package:fiber_pylon/src/storage/valkery_storage.dart' as _i218;
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
    await gh.singletonAsync<_i218.ValkeryStorage>(
      () => _i218.ValkeryStorage.initialize(),
      preResolve: true,
    );
    await gh.singletonAsync<_i167.AppStorage>(
      () => _i167.AppStorage.initialize(gh<_i134.SecureStorage>()),
      preResolve: true,
      dispose: (i) => i.dispose(),
    );
    return this;
  }
}
