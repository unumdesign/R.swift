//
//  Nib.swift
//  R.swift
//
//  Created by Mathijs Kadijk on 09-12-15.
//  From: https://github.com/mac-cain13/R.swift
//  License: MIT License
//

import Foundation

private let ElementNameToTypeMapping = [
  // TODO: Should contain all standard view elements, like button -> UIButton, view -> UIView etc
  "view": Type._UIView,
  "tableViewCell": Type._UITableViewCell,
  "collectionViewCell": Type._UICollectionViewCell,
  "collectionReusableView": Type._UICollectionReusableView
]

struct Nib: WhiteListedExtensionsResourceType, ReusableContainer {
  static let supportedExtensions: Set<String> = ["xib"]

  let name: String
  let rootViews: [Type]
  let reusables: [Reusable]
  let usedImageIdentifiers: [NameCatalog]
  let usedColorResources: [NameCatalog]
  let usedAccessibilityIdentifiers: [String]
  let deploymentVersion: String?

  init(url: URL) throws {
    try Nib.throwIfUnsupportedExtension(url.pathExtension)

    guard let filename = url.filename else {
      throw ResourceParsingError.parsingFailed("Couldn't extract filename from URL: \(url)")
    }
    name = filename

    guard let parser = XMLParser(contentsOf: url) else {
      throw ResourceParsingError.parsingFailed("Couldn't load file at: '\(url)'")
    }

    let parserDelegate = NibParserDelegate()
    parser.delegate = parserDelegate

    guard parser.parse() else {
        throw ResourceParsingError.parsingFailed("Invalid XML in file at: '\(url)'")
    }

    rootViews = parserDelegate.rootViews
    reusables = parserDelegate.reusables
    usedImageIdentifiers = parserDelegate.usedImageIdentifiers
    usedColorResources = parserDelegate.usedColorReferences
    usedAccessibilityIdentifiers = parserDelegate.usedAccessibilityIdentifiers
    deploymentVersion = parseDeploymentVersion(parserDelegate.deploymentVersions) {
      warn("Nib \(filename) contains multiple deployment versions. Unknown how to parse, ignoring all.")
    }
  }
}

internal class NibParserDelegate: NSObject, XMLParserDelegate {
  let ignoredRootViewElements = ["placeholder"]
  var rootViews: [Type] = []
  var reusables: [Reusable] = []
  var usedImageIdentifiers: [NameCatalog] = []
  var usedColorReferences: [NameCatalog] = []
  var usedAccessibilityIdentifiers: [String] = []
  var deploymentVersions: [String] = []

  // State
  var isObjectsTagOpened = false;
  var levelSinceObjectsTagOpened = 0;

  @objc func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String]) {
    if isObjectsTagOpened {
      levelSinceObjectsTagOpened += 1
    }
    if elementName == "objects" {
      isObjectsTagOpened = true
    }
    
    switch elementName {
    case "image":
      if let imageIdentifier = attributeDict["name"] {
        usedImageIdentifiers.append(NameCatalog(name: imageIdentifier, catalog: attributeDict["catalog"]))
      }

    case "color":
      if let colorName = attributeDict["name"] {
        usedColorReferences.append(NameCatalog(name: colorName, catalog: attributeDict["catalog"]))
      }

    case "accessibility":
      if let accessibilityIdentifier = attributeDict["identifier"] {
        usedAccessibilityIdentifiers.append(accessibilityIdentifier)
      }

    case "deployment":
      if let version = attributeDict["version"] {
        deploymentVersions.append(version)
      }

    case "userDefinedRuntimeAttribute":
      if let accessibilityIdentifier = attributeDict["value"], "accessibilityIdentifier" == attributeDict["keyPath"] && "string" == attributeDict["type"] {
        usedAccessibilityIdentifiers.append(accessibilityIdentifier)
      }

    default:
      if let rootView = viewWithAttributes(attributeDict, elementName: elementName),
        levelSinceObjectsTagOpened == 1 && ignoredRootViewElements.allSatisfy({ $0 != elementName }) {
        rootViews.append(rootView)
      }
      if let reusable = reusableFromAttributes(attributeDict, elementName: elementName) {
        reusables.append(reusable)
      }
    }
  }

  @objc func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
    switch elementName {
    case "objects":
      isObjectsTagOpened = false;

    default:
      if isObjectsTagOpened {
        levelSinceObjectsTagOpened -= 1
      }
    }
  }

  func viewWithAttributes(_ attributeDict: [String : String], elementName: String) -> Type? {
    let customModuleProvider = attributeDict["customModuleProvider"]
    let customModule = (customModuleProvider == "target") ? nil : attributeDict["customModule"]
    let customClass = attributeDict["customClass"]
    let customType = customClass
      .map { SwiftIdentifier(name: $0, lowercaseStartingCharacters: false) }
      .map { Type(module: Module(name: customModule), name: $0, optional: false) }

    return customType ?? ElementNameToTypeMapping[elementName] ?? Type._UIView
  }

  func reusableFromAttributes(_ attributeDict: [String : String], elementName: String) -> Reusable? {
    guard let reuseIdentifier = attributeDict["reuseIdentifier"] , reuseIdentifier != "" else {
      return nil
    }

    let customModuleProvider = attributeDict["customModuleProvider"]
    let customModule = (customModuleProvider == "target") ? nil : attributeDict["customModule"]
    let customClass = attributeDict["customClass"]
    let customType = customClass
      .map { SwiftIdentifier(name: $0, lowercaseStartingCharacters: false) }
      .map { Type(module: Module(name: customModule), name: $0, optional: false) }

    let type = customType ?? ElementNameToTypeMapping[elementName] ?? Type._UIView

    return Reusable(identifier: reuseIdentifier, type: type)
  }
}

func parseDeploymentVersion(_ inputs: [String], multipleWarning: () -> Void) -> String? {
  if inputs.count > 1 {
    multipleWarning()
    return nil
  }

  guard let str = inputs.first, let version = Int(str) else { return nil }

  return deploymentVersions[version]
}


// See: https://github.com/mac-cain13/R.swift/issues/511#issuecomment-505867273
// We could write code for this, instead of this hardcoded table. Or not...
private let deploymentVersions: [Int: String] = [
  0x700: "7.0",
  0x710: "7.1",

  0x800: "8.0",
  0x810: "8.1",
  0x830: "8.2",
  0x820: "8.3",

  0x900: "9.0",
  0x910: "9.1",
  0x930: "9.2",
  0x920: "9.3",

  0x1000: "10.0",
  0x1010: "10.1",
  0x1030: "10.2",
  0x1020: "10.3",

  0x1100: "11.0",
  0x1110: "11.1",
  0x1130: "11.2",
  0x1120: "11.3",

  0x1200: "12.0",
  0x1210: "12.1",
  0x1230: "12.2",
  0x1220: "12.3",

  0x1300: "13.0",
  0x1310: "13.1",
  0x1330: "13.2",
  0x1320: "13.3",

  // Future proofing below...
  0x1400: "14.0",
  0x1410: "14.1",
  0x1430: "14.2",
  0x1420: "14.3",

  0x1500: "15.0",
  0x1510: "15.1",
  0x1530: "15.2",
  0x1520: "15.3",

  0x1600: "16.0",
  0x1610: "16.1",
  0x1630: "16.2",
  0x1620: "16.3",

  0x1700: "17.0",
  0x1710: "17.1",
  0x1730: "17.2",
  0x1720: "17.3",

  0x1800: "18.0",
  0x1810: "18.1",
  0x1830: "18.2",
  0x1820: "18.3",

  0x1900: "19.0",
  0x1910: "19.1",
  0x1930: "19.2",
  0x1920: "19.3",
]
