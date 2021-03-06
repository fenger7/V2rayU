//
//  Menu.swift
//  V2rayU
//
//  Created by yanue on 2018/10/16.
//  Copyright © 2018 yanue. All rights reserved.
//

import Foundation
import Cocoa
import ServiceManagement
import Preferences

let menuController = (NSApplication.shared.delegate as? AppDelegate)?.statusMenu.delegate as! MenuController
let preferencesWindowController = PreferencesWindowController(
        viewControllers: [
            PreferenceGeneralViewController(),
        ]
)
var configWindow = ConfigWindowController()
var qrcodeWindow = QrcodeWindowController()

// menu controller
class MenuController: NSObject, NSMenuDelegate {
    var closedByConfigWindow: Bool = false
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var statusItemClicked: (() -> Void)?

    @IBOutlet weak var v2rayRulesMode: NSMenuItem!
    @IBOutlet weak var globalMode: NSMenuItem!
    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var toggleV2rayItem: NSMenuItem!
    @IBOutlet weak var v2rayStatusItem: NSMenuItem!
    @IBOutlet weak var serverItems: NSMenuItem!

    // when menu.xib loaded
    override func awakeFromNib() {
        // Do any additional setup after loading the view.
        // initial auth ref
        let error = AuthorizationCreate(nil, nil, [], &V2rayLaunch.authRef)
        assert(error == errAuthorizationSuccess)

        if UserDefaults.getBool(forKey: .globalMode) {
            self.globalMode.state = .on
            self.v2rayRulesMode.state = .off
        } else {
            self.globalMode.state = .off
            self.v2rayRulesMode.state = .on
        }

        statusMenu.delegate = self
        NSLog("start menu")
        // load server list
        V2rayServer.loadConfig()
        // show server list
        self.showServers()

        statusItem.menu = statusMenu

//        self.configWindow = ConfigWindowController()

        if UserDefaults.getBool(forKey: .v2rayTurnOn) {
            // start
            // on status
            self.startV2rayCore()
        } else {
            // show off status
            self.setStatusOff()
        }

        // windowWillClose Notification
        NotificationCenter.default.addObserver(self, selector: #selector(configWindowWillClose(notification:)), name: NSWindow.willCloseNotification, object: nil)
    }

    @IBAction func openLogs(_ sender: NSMenuItem) {
        V2rayLaunch.OpenLogs()
    }

    func setStatusOff() {
        v2rayStatusItem.title = "V2ray-Core: Off"
        toggleV2rayItem.title = "Turn V2ray-Core On"

        if let button = statusItem.button {
            button.image = NSImage(named: NSImage.Name("IconOff"))
        }

        // set off
        UserDefaults.setBool(forKey: .v2rayTurnOn, value: false)
    }

    func setStatusOn() {
        v2rayStatusItem.title = "V2ray-Core: On"
        toggleV2rayItem.title = "Turn V2ray-Core Off"

        if let button = statusItem.button {
            button.image = NSImage(named: NSImage.Name("IconOn"))
        }

        // set on
        UserDefaults.setBool(forKey: .v2rayTurnOn, value: true)
    }

    func stopV2rayCore() {
        // set status
        self.setStatusOff()
        // stop launch
        V2rayLaunch.Stop()
    }

    // start v2ray core
    func startV2rayCore() {
        NSLog("start v2ray-core begin")

        guard let v2ray = V2rayServer.loadSelectedItem() else {
            self.notice(title: "start v2ray fail", subtitle: "", informativeText: "v2ray config not found")
            return
        }

        if !v2ray.isValid {
            self.notice(title: "start v2ray fail", subtitle: "", informativeText: "invalid v2ray config")
            return
        }

        // create json file
        V2rayConfig.createJsonFile(item: v2ray)

        // set status
        setStatusOn()

        // launch
        V2rayLaunch.Start()
        NSLog("start v2ray-core done.")

        // if enable system proxy
        if UserDefaults.getBool(forKey: .globalMode) {
            // reset system proxy
            self.enableSystemProxy()
        }
    }

    @IBAction func start(_ sender: NSMenuItem) {
        // turn off
        if UserDefaults.getBool(forKey: .v2rayTurnOn) {
            self.stopV2rayCore()
            return
        }

        // start
        self.startV2rayCore()
    }

    @IBAction func quitClicked(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(self)
    }

    @IBAction func generateQRCode(_ sender: NSMenuItem) {
        NSLog("GenerateQRCode")
    }

    @IBAction func scanQRCode(_ sender: NSMenuItem) {
        NSLog("ScanQRCode")
    }

    @IBAction func openPreference(_ sender: NSMenuItem) {
        preferencesWindowController.showWindow()
    }

    // switch server
    @IBAction func switchServer(_ sender: NSMenuItem) {
        guard let obj = sender.representedObject as? V2rayItem else {
            NSLog("switchServer err")
            return
        }

        if !obj.isValid {
            NSLog("current server is invaid", obj.remark)
            return
        }
        // set current
        UserDefaults.set(forKey: .v2rayCurrentServerName, value: obj.name)
        // stop first
        V2rayLaunch.Stop()
        // start
        startV2rayCore()
        // reload menu
        self.showServers()
    }

    // open config window
    @IBAction func openConfig(_ sender: NSMenuItem) {
        // close before
        configWindow.close()
        // renew
        configWindow = ConfigWindowController()
        // show window
        configWindow.showWindow(self)
        // center
        configWindow.window?.center()
        // show dock icon
        NSApp.setActivationPolicy(.regular)
        // bring to front
        NSApp.activate(ignoringOtherApps: true)
    }

    /// When a window was closed this methods takes care of releasing its controller.
    ///
    /// - parameter notification: The notification.
    @objc private func configWindowWillClose(notification: Notification) {
        guard let object = notification.object as? NSWindow else {
            return
        }

        // config window title is "V2rayU"
        if object.title == "V2rayU" {
            self.hideDock()
        }
    }

    func hideDock() {
        // hide dock icon and close all opened windows
        NSApp.setActivationPolicy(.accessory)
        // close by config window
        self.closedByConfigWindow = true
        // close
        configWindow.close()
    }

    @IBAction func goHelp(_ sender: NSMenuItem) {
        guard let url = URL(string: "https://github.com/yanue/v2rayu/wiki") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func showServers() {
        // reomve old items
        serverItems.submenu?.removeAllItems()
        let curSer = UserDefaults.get(forKey: .v2rayCurrentServerName)

        // add new
        var validCount = 0
        for item in V2rayServer.list() {
            if !item.isValid {
                continue
            }

            let menuItem: NSMenuItem = NSMenuItem()
            menuItem.title = item.remark
            menuItem.action = #selector(self.switchServer(_:))
            menuItem.representedObject = item
            menuItem.target = self
            menuItem.isEnabled = true

            if curSer == item.name || V2rayServer.count() == 1 {
                menuItem.state = NSControl.StateValue.on
            }

            serverItems.submenu?.addItem(menuItem)
            validCount += 1
        }

        if validCount == 0 {
            let menuItem: NSMenuItem = NSMenuItem()
            menuItem.title = "no available servers."
            menuItem.isEnabled = false
            serverItems.submenu?.addItem(menuItem)
        }
    }

    @IBAction func disableGlobalProxy(_ sender: NSMenuItem) {
        // state
        self.globalMode.state = .off
        self.v2rayRulesMode.state = .on
        // save
        UserDefaults.setBool(forKey: .globalMode, value: false)
        // disable
        V2rayLaunch.setSystemProxy(enabled: false)
    }

    // MARK: - actions
    @IBAction func enableGlobalProxy(_ sender: NSMenuItem) {
        enableSystemProxy()
    }

    func enableSystemProxy() {
        // save
        UserDefaults.setBool(forKey: .globalMode, value: true)
        // state
        self.globalMode.state = .on
        self.v2rayRulesMode.state = .off

        // enable
        var sockPort = ""
        var httpPort = ""

        let v2ray = V2rayServer.loadSelectedItem()

        if v2ray != nil && v2ray!.isValid {
            let cfg = V2rayConfig()
            cfg.parseJson(jsonText: v2ray!.json)
            sockPort = cfg.socksPort
            httpPort = cfg.httpPort
        }

        V2rayLaunch.setSystemProxy(enabled: true, httpPort: httpPort, sockPort: sockPort)
    }

    @IBAction func generateQrcode(_ sender: NSMenuItem) {
        guard let v2ray = V2rayServer.loadSelectedItem() else {
            NSLog("v2ray config not found")
            self.notice(title: "generate Qrcode fail", subtitle: "", informativeText: "no available servers")
            return
        }

        let share = ShareUri()
        share.qrcode(item: v2ray)
        if share.error.count > 0 {
            self.notice(title: "generate Qrcode fail", subtitle: "", informativeText: share.error)
            return
        }

        // close before
        qrcodeWindow.close()
        // renew
        qrcodeWindow = QrcodeWindowController()
        // show window
        qrcodeWindow.showWindow(nil)
        // center
        qrcodeWindow.window?.center()
        // set uri
        qrcodeWindow.setShareUri(uri: share.uri)
        // bring to front
        NSApp.activate(ignoringOtherApps: true)
    }

    @IBAction func scanQrcode(_ sender: NSMenuItem) {
        let uri: String = Scanner.scanQRCodeFromScreen()
        if uri.count > 0 {
            self.importUri(url: uri)
        } else {
            self.notice(title: "import server fail", subtitle: "", informativeText: "no found qrcode")
        }
    }

    @IBAction func ImportFromPasteboard(_ sender: NSMenuItem) {
        if let uri = NSPasteboard.general.string(forType: .string), uri.count > 0 {
            self.importUri(url: uri)
        } else {
            self.notice(title: "import server fail", subtitle: "", informativeText: "no found ss:// or vmess:// from Pasteboard")
        }
    }

    func importUri(url: String) {
        let uri = url.trimmingCharacters(in: .whitespaces)

        if uri.count == 0 {
            self.notice(title: "import server fail", subtitle: "", informativeText: "import error: uri not found")
            return
        }

        if URL(string: uri) == nil {
            self.notice(title: "import server fail", subtitle: "", informativeText: "no found ss:// or vmess://")
            return
        }

        if uri.hasPrefix("vmess://") {
            let importUri = ImportUri()
            importUri.importVmessUri(uri: uri)
            self.saveServer(importUri: importUri)
            return
        }

        if uri.hasPrefix("ss://") {
            let importUri = ImportUri()
            importUri.importSSUri(uri: uri)
            self.saveServer(importUri: importUri)
            return
        }

        self.notice(title: "import server fail", subtitle: "", informativeText: "no found ss:// or vmess://")
    }

    func notice(title: String = "", subtitle: String = "", informativeText: String = "") {
        // 定义NSUserNotification
        let userNotification = NSUserNotification()
        userNotification.title = title
        userNotification.subtitle = subtitle
        userNotification.informativeText = informativeText
        // 使用NSUserNotificationCenter发送NSUserNotification
        let userNotificationCenter = NSUserNotificationCenter.default
        userNotificationCenter.scheduleNotification(userNotification)
    }

    func saveServer(importUri: ImportUri) {
        if importUri.isValid {
            // add server
            V2rayServer.add(remark: importUri.remark, json: importUri.json, isValid: true, url: importUri.uri)
            // refresh server
            self.showServers()

            self.notice(title: "import server success", subtitle: "", informativeText: importUri.remark)
        } else {
            self.notice(title: "import server fail", subtitle: "", informativeText: importUri.error)
        }
    }

}
