part of di;

List<Key> _PRIMITIVE_TYPES = new UnmodifiableListView(<Key>[
  new Key(num), new Key(int), new Key(double), new Key(String),
  new Key(bool)
]);

abstract class ObjectFactory {
  Object getInstanceByKey(Key key, Injector requester, List resolving);
}

abstract class Injector implements ObjectFactory {
  /**
   * Name of the injector or null of none is given.
   */
  String get name;

  /**
   * The parent injector or null if root.
   */
  Injector get parent;

  /**
   * The root injector.
   */
  Injector get root;

  /**
   * List of all types which the injector can return
   */
  Set<Type> get types;

  /**
   * Indicates whether injector allows implicit injection -- resolving types
   * that were not explicitly bound in the module(s).
   */
  bool get allowImplicitInjection;

  /**
   * Get an instance for given token ([Type]).
   *
   * If the injector already has an instance for this token, it returns this
   * instance. Otherwise, injector resolves all its dependencies, instantiates
   * new instance and returns this instance.
   *
   * If there is no binding for given token, injector asks parent injector.
   *
   * If there is no parent injector, an implicit binding is used. That is,
   * the token ([Type]) is instantiated.
   */
  dynamic get(Type type, [Type annotation]);

  /**
   * Get an instance for given key ([Key]).
   *
   * If the injector already has an instance for this key, it returns this
   * instance. Otherwise, injector resolves all its dependencies, instantiates
   * new instance and returns this instance.
   *
   * If there is no binding for given key, injector asks parent injector.
   */
  dynamic getByKey(Key key);

  /**
   * Create a child injector.
   *
   * Child injector can override any bindings by adding additional modules.
   *
   * It also accepts a list of tokens that a new instance should be forced.
   * That means, even if some parent injector already has an instance for this
   * token, there will be a new instance created in the child injector.
   */
  Injector createChild(List<Module> modules,
                       {List forceNewInstances, String name});


  newFromParent(List<Module> modules, String name);

  Object newInstanceOf(Type type, ObjectFactory factory, Injector requestor,
                       resolving);
}

abstract class BaseInjector implements Injector {

  @override
  final String name;

  @override
  final BaseInjector parent;

  Injector _root;

  List<_Provider> _providers;
  int _providersLen = 0;

  final Map<Key, Object> _instances = <Key, Object>{};

  @override
  final bool allowImplicitInjection;

  Iterable<Type> _typesCache;

  Iterable<Type> get _types {
    if (_providers == null) return [];

    if (_typesCache == null) {
      _typesCache = _providers
          .where((p) => p != null)
          .map((p) => p.type);
    }
    return _typesCache;
  }

  BaseInjector({List<Module> modules, String name,
           bool allowImplicitInjection: false})
      : this.fromParent(modules, null,
          name: name, allowImplicitInjection: allowImplicitInjection);

  BaseInjector.fromParent(List<Module> modules,
      BaseInjector this.parent, {this.name, this.allowImplicitInjection}) {
    _root = parent == null ? this : parent._root;
    var injectorId = new Key(Injector).id;
    _providers = new List(_lastKeyId + 1);
    _providersLen = _lastKeyId + 1;
    if (modules != null) {
      modules.forEach((module) {
        module._bindings.forEach((k, v) {
          _providers[k] = v;
        });
      });
    }
    _providers[injectorId] = new _ValueProvider(Injector, this);
  }

  @override
  Injector get root => _root;

  @override
  Set<Type> get types {
    var types = new Set.from(_types);
    var parent = this.parent;
    while (parent != null) {
      types.addAll(parent._types);
      parent = parent.parent;
    }
    return types;
  }

  // 'resolving' is a tuple of (depth, Key, cdr), I implemented it
  // as an array, but there may be a better solution.
  static const ZERO_DEPTH_RESOLVING = const [0];

  Object getInstanceByKey(Key key, Injector requester, List resolving) {
    assert(_checkKeyConditions(key, resolving));

    // Do not bother checking the array until we are fairly deep.
    if (resolving[0] > 30 && resolvedTypes(resolving).contains(key)) {
      throw new CircularDependencyError(
          error(resolving, 'Cannot resolve a circular dependency!', key));
    }

    var providerWithInjector = _getProviderWithInjectorForKey(key, resolving);
    var provider = providerWithInjector.provider;
    var injector = providerWithInjector.injector;
    var visible = provider.visibility != null ?
        provider.visibility(requester, injector) :
        _defaultVisibility(requester, injector);

    if (visible && _instances.containsKey(key)) return _instances[key];

    if (providerWithInjector.injector != this || !visible) {
      if (!visible) {
        if (injector.parent == null) {
          throw new NoProviderError(
              error(resolving, 'No provider found for ${key}!', key));
        }
        injector =
            injector.parent._getProviderWithInjectorForKey(key, resolving).injector;
      }
      return injector.getInstanceByKey(key, requester, resolving);
    }

    resolving = [resolving[0] + 1, key, resolving];
    var value = provider.get(this, requester, this, resolving);

    // cache the value.
    providerWithInjector.injector._instances[key] = value;
    return value;
  }

  /// Returns a pair for provider and the injector where it's defined.
  _ProviderWithDefiningInjector _getProviderWithInjectorForKey(
      Key key, List resolving) {
    if (key.id < _providersLen) {
      var provider = _providers[key.id];
      if (provider != null) {
        return new _ProviderWithDefiningInjector(provider, this);
      }
    }

    if (parent != null) {
      return parent._getProviderWithInjectorForKey(key, resolving);
    }

    if (allowImplicitInjection) {
      return new _ProviderWithDefiningInjector(
          new _TypeProvider(key.type), this);
    }

    throw new NoProviderError(error(resolving, 'No provider found for ${key}!', key));
  }

  bool _checkKeyConditions(Key key, List resolving) {
    if (_PRIMITIVE_TYPES.contains(key)) {
      throw new NoProviderError(error(resolving, 'Cannot inject a primitive type '
          'of ${key.type}!', key));
    }
    return true;
  }

  @override
  dynamic get(Type type, [Type annotation]) =>
      getInstanceByKey(new Key(type, annotation), this, BaseInjector.ZERO_DEPTH_RESOLVING);

  @override
  dynamic getByKey(Key key) => getInstanceByKey(key, this, BaseInjector.ZERO_DEPTH_RESOLVING);

  @override
  Injector createChild(List<Module> modules,
                       {List forceNewInstances, String name}) =>
      _createChildWithResolvingHistory(modules, BaseInjector.ZERO_DEPTH_RESOLVING,
          forceNewInstances: forceNewInstances,
          name: name);

  Injector _createChildWithResolvingHistory(
                        List<Module> modules,
                        resolving,
                        {List forceNewInstances, String name}) {
    if (forceNewInstances != null) {
      Module forceNew = new Module();
      forceNewInstances.forEach((key) {
        if (key is Type) {
          key = new Key(key);
        } else if (key is! Key) {
          throw 'forceNewInstances must be List<Key|Type>';
        }
        assert(key is Key);
        var providerWithInjector = _getProviderWithInjectorForKey(key, resolving);
        var provider = providerWithInjector.provider;
        forceNew._keyedFactory(key, (Injector inj) => provider.get(this,
            inj, inj, resolving),
            visibility: provider.visibility);
      });

      modules = modules.toList(); // clone
      modules.add(forceNew);
    }

    return newFromParent(modules, name);
  }
}

class _ProviderWithDefiningInjector {
  final _Provider provider;
  final BaseInjector injector;
  _ProviderWithDefiningInjector(this.provider, this.injector);
}
