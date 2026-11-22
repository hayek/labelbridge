// usage: swift cutout.swift <in> <out.png>  — foreground cut-out with Vision, transparent background
import AppKit
import Vision
import CoreImage
let input = CIImage(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))!
let req = VNGenerateForegroundInstanceMaskRequest()
let handler = VNImageRequestHandler(ciImage: input)
try handler.perform([req])
guard let obs = req.results?.first else { print("no foreground"); exit(1) }
let buf = try obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler, croppedToInstancesExtent: true)
let out = CIImage(cvPixelBuffer: buf)
let ctx = CIContext()
let cg = ctx.createCGImage(out, from: out.extent)!
try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
print("cutout \(cg.width)x\(cg.height)")
