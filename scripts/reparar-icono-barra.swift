#!/usr/bin/env swift

import Foundation

// Herramienta EXCLUSIVA del flujo de desarrollo local. macOS 26 puede asociar
// un status item a la aplicación que lo lanzó (por ejemplo, Codex) y ocultarlo
// si esa aplicación está desactivada en la barra. La app instalada no debe pedir
// Acceso total al disco para corregir un bug del sistema; por eso esta reparación
// corre desde la terminal que compila e instala BtoDicta y NO viaja en el DMG.

let bundleBeto = "ec.bto.btodicta"
let preferenciasURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Group Containers/group.com.apple.controlcenter")
    .appendingPathComponent("Library/Preferences/group.com.apple.controlcenter.plist")

func bundle(de valor: Any?) -> String? {
    guard let contenedor = valor as? [String: Any],
          let bundle = contenedor["bundle"] as? [String: Any] else { return nil }
    return bundle["_0"] as? String
}

/// Se niega a modificar si BtoDicta no conserva su propia fila permitida.
func limpiar(
    entradas: [[String: Any]], bundleObjetivo: String
) -> (entradas: [[String: Any]], eliminadas: Int)? {
    let propiaPermitida = entradas.contains { entrada in
        bundle(de: entrada["location"]) == bundleObjetivo
            && (entrada["isAllowed"] as? Bool) == true
    }
    guard propiaPermitida else { return nil }

    var resultado = entradas
    var eliminadas = 0
    for indice in resultado.indices {
        var entrada = resultado[indice]
        guard let propietario = bundle(de: entrada["location"]),
              propietario != bundleObjetivo,
              let ubicaciones = entrada["menuItemLocations"] as? [[String: Any]] else { continue }
        let limpias = ubicaciones.filter { ubicacion in
            let cruzada = bundle(de: ubicacion) == bundleObjetivo
            if cruzada { eliminadas += 1 }
            return !cruzada
        }
        if limpias.count != ubicaciones.count {
            entrada["menuItemLocations"] = limpias
            resultado[indice] = entrada
        }
    }
    return (resultado, eliminadas)
}

func ejecutar(_ ruta: String, _ argumentos: [String]) -> Bool {
    let proceso = Process()
    proceso.executableURL = URL(fileURLWithPath: ruta)
    proceso.arguments = argumentos
    proceso.standardOutput = FileHandle.nullDevice
    proceso.standardError = FileHandle.nullDevice
    do {
        try proceso.run()
        proceso.waitUntilExit()
        return proceso.terminationStatus == 0
    } catch {
        return false
    }
}

func hex(_ datos: Data) -> String {
    datos.map { String(format: "%02x", $0) }.joined()
}

func probar() -> Bool {
    func nodo(_ id: String) -> [String: Any] { ["bundle": ["_0": id]] }
    let propia: [String: Any] = [
        "isAllowed": true,
        "location": nodo(bundleBeto),
        "menuItemLocations": [nodo(bundleBeto)],
    ]
    let extranjera: [String: Any] = [
        "isAllowed": false,
        "location": nodo("com.ejemplo.otra"),
        "menuItemLocations": [nodo("com.ejemplo.otra"), nodo(bundleBeto)],
    ]
    guard let limpia = limpiar(entradas: [propia, extranjera], bundleObjetivo: bundleBeto),
          limpia.eliminadas == 1,
          let restantes = limpia.entradas[1]["menuItemLocations"] as? [[String: Any]],
          restantes.count == 1,
          bundle(de: restantes[0]) == "com.ejemplo.otra" else { return false }

    var propiaBloqueada = propia
    propiaBloqueada["isAllowed"] = false
    return limpiar(entradas: [propiaBloqueada, extranjera], bundleObjetivo: bundleBeto) == nil
}

if CommandLine.arguments.contains("--probar") {
    let ok = probar()
    print("MENUBARGUARDTEST \(ok ? "TODO OK" : "FALLA")")
    exit(ok ? 0 : 3)
}

do {
    let original = try Data(contentsOf: preferenciasURL)
    guard let exterior = try PropertyListSerialization.propertyList(
        from: original, options: [], format: nil
    ) as? [String: Any],
    let datosRastreados = exterior["trackedApplications"] as? Data,
    let entradas = try PropertyListSerialization.propertyList(
        from: datosRastreados, options: [], format: nil
    ) as? [[String: Any]],
    let limpieza = limpiar(entradas: entradas, bundleObjetivo: bundleBeto) else {
        print("MENUBARREPAIR OMITIDO: no existe una fila propia permitida de BtoDicta")
        exit(0)
    }
    guard limpieza.eliminadas > 0 else {
        print("MENUBARREPAIR SIN CAMBIOS")
        exit(0)
    }

    let carpeta = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".btodicta/backups", isDirectory: true)
    try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: carpeta.path)
    let formato = DateFormatter()
    formato.locale = Locale(identifier: "en_US_POSIX")
    formato.dateFormat = "yyyyMMdd-HHmmss"
    let respaldo = carpeta.appendingPathComponent(
        "controlcenter-antes-icono-\(formato.string(from: Date())).plist"
    )
    try original.write(to: respaldo, options: [.atomic])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: respaldo.path)

    let nuevosRastreados = try PropertyListSerialization.data(
        fromPropertyList: limpieza.entradas, format: .binary, options: 0
    )
    let dominio = preferenciasURL.deletingPathExtension().path
    guard ejecutar("/usr/bin/defaults", [
        "write", dominio, "trackedApplications", "-data", hex(nuevosRastreados),
    ]) else {
        print("MENUBARREPAIR FALLA: no pude guardar; respaldo=\(respaldo.path)")
        exit(4)
    }
    _ = ejecutar("/usr/bin/killall", ["ControlCenter"])
    print("MENUBARREPAIR REPARADO \(limpieza.eliminadas) · respaldo 0600")
} catch {
    print("MENUBARREPAIR FALLA: \(error.localizedDescription)")
    exit(5)
}
