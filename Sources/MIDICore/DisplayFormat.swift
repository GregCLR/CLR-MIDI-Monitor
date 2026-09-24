import Foundation

public enum ValueFormat: String, CaseIterable { case name = "Name", decimal = "Decimal number" }
public enum MiddleC: String, CaseIterable { case c3 = "C3", c4 = "C4" }
public struct EventDisplay {
    public let parameterLabel: String
    public let parameter: String
    public let valueLabel: String
    public let value: String
    public var summary: String { parameter == "—" ? value : "\(parameter) · \(value)" }
}
public enum MIDIFormat {
    public static func note(_ number: Int, format: ValueFormat, middleC: MiddleC) -> String {
        guard format == .name else { return String(number) }
        return ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"][number % 12] + String(number / 12 - (middleC == .c3 ? 2 : 1))
    }
    public static func controller(_ number: Int, format: ValueFormat) -> String {
        guard format == .name else { return String(number) }
        let names = [0:"Bank Select",1:"Modulation",2:"Breath",4:"Foot Controller",5:"Portamento Time",6:"Data Entry",7:"Volume",8:"Balance",10:"Pan",11:"Expression",12:"Effect Control 1",13:"Effect Control 2",16:"General Purpose 1",17:"General Purpose 2",18:"General Purpose 3",19:"General Purpose 4",64:"Sustain",65:"Portamento",66:"Sostenuto",67:"Soft Pedal",68:"Legato",69:"Hold 2",70:"Sound Variation",71:"Resonance",72:"Release Time",73:"Attack Time",74:"Brightness",75:"Decay Time",76:"Vibrato Rate",77:"Vibrato Depth",78:"Vibrato Delay",80:"General Purpose 5",81:"General Purpose 6",82:"General Purpose 7",83:"General Purpose 8",88:"High Resolution Velocity",84:"Portamento Control",91:"Reverb",92:"Tremolo",93:"Chorus",94:"Detune",95:"Phaser",96:"Data Increment",97:"Data Decrement",98:"NRPN LSB",99:"NRPN MSB",100:"RPN LSB",101:"RPN MSB",120:"All Sound Off",121:"Reset Controllers",122:"Local Control",123:"All Notes Off",124:"Omni Off",125:"Omni On",126:"Mono Mode",127:"Poly Mode"]
        if let name = names[number] { return name }
        if (32...63).contains(number), let base = names[number - 32] { return base + " LSB" }
        return String(number)
    }
    public static func display(_ event: MIDIEvent, notes: ValueFormat, controllers: ValueFormat, middleC: MiddleC) -> EventDisplay {
        guard let w = event.words.first, w >> 28 == 2, event.kind != "Malformed" else {
            return EventDisplay(parameterLabel: "DATA", parameter: "—", valueLabel: "VALUE", value: event.channel == nil && ["Clock","Active Sensing","Start","Stop","Continue","Reset","Tune Request"].contains(event.kind) ? "—" : event.detail)
        }
        let status = (w >> 16) & 255, a = Int((w >> 8) & 127), b = Int(w & 127)
        switch status >> 4 {
        case 8,9,10:
            return EventDisplay(parameterLabel: "NOTE", parameter: note(a, format: notes, middleC: middleC), valueLabel: status >> 4 == 10 ? "PRESSURE" : "VELOCITY", value: String(b))
        case 11:
            return EventDisplay(parameterLabel: "CONTROLLER", parameter: controller(a, format: controllers), valueLabel: "VALUE", value: String(b))
        case 12: return EventDisplay(parameterLabel: "PROGRAM", parameter: String(a), valueLabel: "VALUE", value: "—")
        case 13: return EventDisplay(parameterLabel: "DATA", parameter: "—", valueLabel: "PRESSURE", value: String(a))
        case 14: return EventDisplay(parameterLabel: "DATA", parameter: "—", valueLabel: "BEND", value: String((b << 7 | a) - 8192))
        default: return EventDisplay(parameterLabel: "DATA", parameter: "—", valueLabel: "VALUE", value: event.detail)
        }
    }
}
