import DriveSimulation
import Foundation
import SensorCore
import Testing

struct DetectionPipelineTests {
    @Test(arguments: PhoneOrientation.testPlacements)
    func `detects a hard brake`(orientation: PhoneOrientation) {
        let events = detect([.brake(g: 0.45, seconds: 1.5), .cruise(seconds: 4)], orientation: orientation)
        #expect(events.map(\.kind) == [.hardBrake])
    }

    @Test(arguments: PhoneOrientation.testPlacements)
    func `detects hard acceleration`(orientation: PhoneOrientation) {
        let events = detect([.accelerate(g: 0.32, seconds: 2), .cruise(seconds: 4)], orientation: orientation)
        #expect(events.map(\.kind) == [.hardAcceleration])
    }

    /// // Two argument lists run every combination: each placement × left and right.
    @Test(arguments: PhoneOrientation.testPlacements, [true, false])
    func `detects a sharp turn either way`(orientation: PhoneOrientation, toLeft: Bool) {
        let events = detect(
            [.turn(lateralG: 0.4, seconds: 3, toLeft: toLeft), .cruise(seconds: 4)],
            orientation: orientation,
        )
        #expect(events.map(\.kind) == [.sharpTurn])
    }

    @Test(arguments: PhoneOrientation.testPlacements)
    func `detects a swerve`(orientation: PhoneOrientation) {
        let events = detect(
            [.swerve(lateralG: 0.3, secondsPerSide: 0.8), .cruise(seconds: 4)],
            orientation: orientation,
        )
        #expect(events.map(\.kind) == [.swerve])
    }

    @Test(arguments: PhoneOrientation.testPlacements)
    func `detects a bump`(orientation: PhoneOrientation) {
        let events = detect([.bump(g: 0.8), .cruise(seconds: 3)], orientation: orientation)
        #expect(events.map(\.kind) == [.bump])
    }

    @Test(arguments: PhoneOrientation.testPlacements)
    func `ignores normal driving`(orientation: PhoneOrientation) {
        let events = detect(
            [.cruise(seconds: 10), .brake(g: 0.1, seconds: 5), .turn(lateralG: 0.15, seconds: 3), .cruise(seconds: 3)],
            orientation: orientation,
        )
        #expect(events.isEmpty)
    }

    @Test(arguments: PhoneOrientation.testPlacements)
    func `ignores shaking and dropping the phone while parked`(orientation: PhoneOrientation) {
        let segments: [DriveSegment] = [.parked(seconds: 3), .shakePhone(seconds: 10), .dropPhone, .parked(seconds: 3)]
        var pipeline = DetectionPipeline()

        let events = SyntheticDrive(segments: segments, orientation: orientation).readings()
            .flatMap { pipeline.process($0) }

        #expect(events.isEmpty)
    }

    @Test func `records where and how fast a hard brake happened`() throws {
        let events = detect([.brake(g: 0.45, seconds: 1.5), .cruise(seconds: 4)], orientation: .mount)

        let event = try #require(events.first)
        #expect(event.coordinate != nil)
        #expect(event.course != nil)
        // // Warm-up ends near 17.7 m/s and the brake sheds speed, so it should land in between.
        let speed = try #require(event.speed)
        #expect(speed > 11 && speed < 18.5)
        #expect(abs(event.peakAcceleration - 0.45) < 0.08)
        #expect(event.confidence > 0.6)
    }

    /// Runs warm-up + `segments` through a fresh pipeline and returns the detected events.
    private func detect(_ segments: [DriveSegment], orientation: PhoneOrientation) -> [DrivingEvent] {
        var pipeline = DetectionPipeline()
        return SyntheticDrive(segments: DriveSegment.warmUp + segments, orientation: orientation).readings()
            .flatMap { pipeline.process($0) }
    }
}
