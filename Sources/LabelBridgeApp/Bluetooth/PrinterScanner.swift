import CoreBluetooth
import LabelCore

enum PrinterState: Equatable {
    case unauthorized, poweredOff, idle, searching, found(name: String), printing(Int, Int), notFound
}

/// Owns the CoreBluetooth central and finds/connects the D11.
final class PrinterScanner: NSObject, CBCentralManagerDelegate, @unchecked Sendable {
    static let service = CBUUID(string: "E7810A71-73AE-499D-8C15-FAA9AEF0C3F2")
    static let characteristic = CBUUID(string: "BEF8D6C9-9C21-4C9E-B632-BD58C1009F9F")
    static let namePrefix = "D11"

    private var central: CBCentralManager!
    private var poweredOn: OneShot<Void>?
    private var discovered: OneShot<CBPeripheral>?
    private var connected: OneShot<Void>?
    private(set) var links: [UUID: BLEPrinterLink] = [:]
    var onState: ((PrinterState) -> Void)?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    /// Scans for the printer, connects, and returns a ready link.
    @MainActor
    func connect(timeout: Duration = .seconds(15)) async throws -> BLEPrinterLink {
        try await waitForPower()
        onState?(.searching)
        let peripheral = try await OneShot<CBPeripheral>().wait(timeout: timeout, error: PrintError.notFound) { shot in
            if let known = central.retrieveConnectedPeripherals(withServices: [Self.service]).first {
                shot.resume(known)
            } else {
                discovered = shot
                central.scanForPeripherals(withServices: nil)
            }
        } onTimeout: { self.central.stopScan() }
        central.stopScan()
        onState?(.found(name: peripheral.name ?? "D11"))
        try await OneShot<Void>().wait(timeout: .seconds(10), error: PrintError.busy) { shot in
            connected = shot
            central.connect(peripheral)
        } onTimeout: { self.central.cancelPeripheralConnection(peripheral) }
        let link = BLEPrinterLink(peripheral: peripheral, central: central)
        links[peripheral.identifier] = link
        try await link.prepare()
        return link
    }

    @MainActor
    private func waitForPower() async throws {
        switch central.state {
        case .poweredOn: return
        case .unauthorized: onState?(.unauthorized); throw PrintError.notFound
        case .poweredOff: onState?(.poweredOff); throw PrintError.notFound
        default:
            try await OneShot<Void>().wait(timeout: .seconds(5), error: PrintError.notFound) { poweredOn = $0 }
        }
    }

    // MARK: CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        Log.write("bluetooth state \(c.state.rawValue)")
        switch c.state {
        case .poweredOn: MainActor.assumeIsolated { poweredOn?.resume(()) }; onState?(.idle)
        case .unauthorized: onState?(.unauthorized); MainActor.assumeIsolated { poweredOn?.fail(PrintError.notFound) }
        case .poweredOff: onState?(.poweredOff); MainActor.assumeIsolated { poweredOn?.fail(PrintError.notFound) }
        default: break
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi: NSNumber) {
        let name = p.name ?? (ad[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        let services = ad[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard name.hasPrefix(Self.namePrefix) || services.contains(Self.service) else { return }
        MainActor.assumeIsolated {
            guard let shot = discovered, shot.isPending else { return }
            discovered = nil
            Log.write("found \(name)")
            shot.resume(p)
        }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        MainActor.assumeIsolated { connected?.resume(()); connected = nil }
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { connected?.fail(PrintError.busy); connected = nil }
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        Log.write("disconnected \(error.map { "\($0)" } ?? "")")
        links.removeValue(forKey: p.identifier)?.didDisconnect()
        onState?(.idle)
    }
}

