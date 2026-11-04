// Run after building: swift scripts/check-mac-plurals.swift
import Foundation
let resources = URL(fileURLWithPath: "build/DerivedData/Build/Products/Debug/ImmichGallery.app/Contents/Resources")
func localized(_ language: String, _ key: String, _ values: CVarArg...) -> String {
    let bundle = Bundle(url: resources.appendingPathComponent("\(language).lproj"))!
    let format = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
    return String(format: format, locale: Locale(identifier: language), arguments: values)
}
assert(localized("it", "%lld items couldn't be exported.", 1) == "Impossibile esportare 1 elemento.")
assert(localized("it", "%lld items couldn't be exported.", 2) == "Impossibile esportare 2 elementi.")
assert(localized("it", "Choose a folder for %lld original files.", 1) == "Scegli una cartella per 1 file originale.")
assert(localized("it", "Choose a folder for %lld original files.", 2) == "Scegli una cartella per 2 file originali.")
assert(localized("en", "%lld items", 1) == "1 item")
assert(localized("en", "%lld items", 2) == "2 items")
assert(localized("it", "%lld items", 0) == "0 elementi")
assert(localized("it", "%lld items", 1) == "1 elemento")
assert(localized("it", "%lld items", 2) == "2 elementi")
assert(localized("it", "Delete %lld items?", 1) == "Eliminare 1 elemento?")
assert(localized("it", "Permanently delete %lld items?", 2) == "Eliminare definitivamente 2 elementi?")
assert(localized("it", "%lld of %lld selected", 1, 12) == "1 di 12 selezionato")
assert(localized("it", "%lld of %lld selected", 2, 12) == "2 di 12 selezionati")
assert(localized("it", "%lld files exported; %lld failed.", 1, 2) == "1 file esportato; 2 non riusciti.")
assert(localized("it", "%lld files exported; %lld failed.", 2, 1) == "2 file esportati; 1 non riuscito.")
assert(localized("en", "%lld files exported; %lld failed.", 1, 0) == "1 file exported; 0 failed.")
assert(localized("it", "Archive", 0) == "Archivio")
assert(localized("it", "Archive Selected Photos", 0) == "Archivia")
print("Passed compiled Italian/English plurals and archive noun/verb")
