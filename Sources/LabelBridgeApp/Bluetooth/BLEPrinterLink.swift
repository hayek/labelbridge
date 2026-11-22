import CoreBluetooth
import LabelCore

/// `PrinterLink` over the D11's single GATT characteristic (write without response + notify).
final class BLEPrinterLink: NSObject, PrinterLink, CBPeripheralDelegate, @unchecked Sendable {
    let peripheral: CBPeripheral
    private weak var central: CBCentralManager?
    private var characteristic: CBCharacteristic?
    private var parser = FrameParser()
    private var continuation: AsyncStream<Packet>.Continuation!
    let replies: AsyncStream<Packet>
    private var ready: OneShot<Void>?
    private var canSend: OneShot<Void>?
    private var disconnected = false

    init(peripheral: CBPeripheral, central: CBCentralManager) {
        self.peripheral = peripheral
        self.central = central
        var c: AsyncStream<Packet>.Continuation!
        replies = AsyncStream(bufferingPolicy: .unbounded) { c = $0 }
        super.init()
        continuation = c
        peripheral.delegate = self
    }

    /// Discovers the service and characteristic and turns on notifications.
    @MainActor
    func prepare() async throws {
        try await OneShot<Void>().wait(timeout: .seconds(10), error: PrintError.busy) { shot in
            ready = shot
            peripheral.discoverServices([PrinterScanner.service])
        }
    }

    func send(_ bytes: [UInt8]) async throws {
        guard !disconnected, let ch = characteristic else { throw PrintError.timeout }
        let max = peripheral.maximumWriteValueLength(for: .withoutResponse)
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + max, bytes.count)
            try await waitUntilCanSend()
            peripheral.writeValue(Data(bytes[offset..<end]), for: ch, type: .withoutResponse)
            offset = end
        }
    }

    @MainActor
    private func waitUntilCanSend() async throws {
        if peripheral.canSendWriteWithoutResponse { return }
        try await OneShot<Void>().wait(timeout: .seconds(5), error: PrintError.timeout) { canSend = $0 }
    }

    func close() async {
        continuation.finish()
        if !disconnected { central?.cancelPeripheralConnection(peripheral) }
    }

    func didDisconnect() {
        disconnected = true
        continuation.finish()
        MainActor.assumeIsolated { ready?.fail(PrintError.busy); canSend?.fail(PrintError.timeout) }
    }

    // MARK: CBPeripheralDelegate
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == PrinterScanner.service }) else {
            MainActor.assumeIsolated { ready?.fail(PrintError.busy) }; return
        }
        p.discoverCharacteristics([PrinterScanner.characteristic], for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        guard let ch = s.characteristics?.first(where: { $0.uuid == PrinterScanner.characteristic }) else {
            MainActor.assumeIsolated { ready?.fail(PrintError.busy) }; return
        }
        characteristic = ch
        p.setNotifyValue(true, for: ch)
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated { ready?.resume(()) }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        for packet in parser.feed([UInt8](ch.value ?? Data())) { continuation.yield(packet) }
    }

    func peripheralIsReady(toSendWriteWithoutResponse p: CBPeripheral) {
        MainActor.assumeIsolated { canSend?.resume(()); canSend = nil }
    }
}
