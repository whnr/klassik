import Testing

@testable import Klassik

struct SectionFoldsTests {
    @Test func startsOpen() {
        #expect(!SectionFolds().isFolded("Works"))
    }

    @Test func aTapFoldsAndASecondTapOpens() {
        var folds = SectionFolds()
        folds.toggle("Works")
        #expect(folds.isFolded("Works"))
        folds.toggle("Works")
        #expect(!folds.isFolded("Works"))
    }

    @Test func sectionsFoldApart() {
        var folds = SectionFolds()
        folds.toggle("Albums")
        #expect(folds.isFolded("Albums"))
        #expect(!folds.isFolded("Works"))
    }
}
