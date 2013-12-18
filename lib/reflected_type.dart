library di.src.reflected_type;

// These are used by _getReflectedTypeWorkaround, see http://dartbug.com/12607
@MirrorsUsed(targets:
    const ['_js_helper.createRuntimeType', 'dart._js_mirrors.JsClassMirror'],
    override: 'di.src.reflected_type')
import 'dart:mirrors';

// Horrible hack to work around: http://dartbug.com/12607
Type getReflectedTypeWorkaround(ClassMirror cls) {
  // On Dart VM, just return reflectedType.
  if (1.0 is! int) return cls.reflectedType;

  var mangledName = reflect(cls).getField(_mangledNameField).reflectee;
  Type type = _jsHelper.invoke(#createRuntimeType, [mangledName]).reflectee;
  return type;
}

final LibraryMirror _jsHelper =
    currentMirrorSystem().libraries[Uri.parse('dart:_js_helper')];

final Symbol _mangledNameField = () {
  var jsClassMirrorMirror = reflect(reflectClass(ClassMirror)).type;
  for (var name in jsClassMirrorMirror.declarations.keys) {
    if (MirrorSystem.getName(name) == '_mangledName') return name;
  }
}();
