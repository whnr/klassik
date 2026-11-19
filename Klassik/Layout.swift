import SwiftUI

/// The layout values of the specimen: insets, gaps, corners, fixed sizes and text roles.
/// Views take their numbers from here or from `Tokens.swift`; `scripts/layout_lint.py` refuses a literal.
/// The UI walk compiles this file and `Tokens.swift` too, so it measures the screens against the same values.
///
/// Each value cites its source in one line: `css: <file> <selector> | <property>[ | <literal>]`. The file is in
/// `design/specimen/`. `scripts/layout_tokens.py --check` resolves the CSS value through `tokens.css` and fails when
/// it differs from the Swift value. A `<literal>` names a number inside a value that is not one sum, such as
/// `max(min(118vw, 470px), …)`.
///
/// Where the specimen has two values for one role, both are listed, with the pages that use each.
enum Layout {
    // MARK: Page edges

    /// The content inset on both sides without a timeline. The content keeps its width with a timeline.
    /// css: specimen.css :root | --pad-left
    static let centredEdge = Space.l.points + Measure.timeline / 2
    /// The content inset on the side away from a shown timeline.
    /// css: specimen.css :root.has-timeline | --pad-left
    static let edge = Space.l.points
    /// A set member starts at twice the ordinary leading space.
    /// css: person.html "padding-left: calc(var(--space-l) * 2)" | padding-left
    static let setMemberLeading = Space.l.points * 2
    /// The content inset on the side of a shown timeline: the margin of the other side plus the timeline.
    /// css: specimen.css :root.has-timeline | --pad-right
    static let timelineEdge = Space.l.points + Measure.timeline

    /// The left and right page insets. `timelineOnLeft` is nil when no timeline shows.
    static func sideInsets(timelineOnLeft: Bool?) -> (left: CGFloat, right: CGFloat) {
        switch timelineOnLeft {
        case nil: (centredEdge, centredEdge)
        case true?: (timelineEdge, edge)
        case false?: (edge, timelineEdge)
        }
    }

    // MARK: Page heading

    /// The gap above the page title, under the back arrow.
    /// css: specimen.css .page-head | padding-top
    static let headTop = Space.l.points
    /// The gap under the page heading block, after its meta lines.
    /// css: specimen.css .page-head | padding-bottom
    static let headBottom = Space.s.points
    /// The gap from the page title to its meta lines.
    /// Two values: the frame rule gives `space-xxs`; the decided rule gives `space-inGroup` on every page.
    /// css: specimen.css .page-head .meta | margin-top
    static let metaTop = Space.inGroup.points

    // MARK: Sections

    /// The gap above a section heading.
    /// Two values: the frame rule gives `space-xl`; the decided rule gives `space-betweenSections` on every page,
    /// the grouped token sheet included.
    /// css: specimen.css .section | margin-top
    static let sectionTop = Space.betweenSections.points
    /// The gap from a section heading to its first row.
    /// Two values: the frame rule gives `space-xs`; the decided rule gives `space-inGroup` on every page.
    /// css: specimen.css .section-head | padding-bottom
    static let sectionHeadBottom = Space.inGroup.points
    /// The gap above a section footnote.
    /// Two values: `space-xs` on every page; work.html adds a margin of `space-s` above its footnote.
    /// css: specimen.css .section-foot | padding-top
    static let footTop = Space.xs.points
    /// The extra gap above the footnote under the recordings of a work page.
    /// css: work.html "margin: var(--space-s) var(--pad-right) 0 var(--pad-left)" | margin-top
    static let workFootTop = Space.s.points

    // MARK: Rows

    /// The gap above and below the content of a row.
    /// Two values: the frame rule gives `space-s`; the decided rule gives half of `space-betweenGroups` on every
    /// page.
    /// css: specimen.css .row | padding-top
    static let rowPadding = Space.betweenGroups.points / 2
    /// The gap between the parts of a row: cover, text, trailing button.
    /// css: specimen.css .row | gap
    static let rowGap = Space.m.points
    /// The gap between the lines of a row.
    /// css: specimen.css .row .main > * + * | margin-top
    static let rowLineGap = Space.inGroup.points
    /// The gap between the trailing items of a row.
    /// css: specimen.css .row .trail | gap
    static let trailGap = Space.s.points
    /// The cover of a recording row.
    /// css: specimen.css .cover | width
    static let rowCover = Measure.coverRow
    /// css: specimen.css .cover | border-top-left-radius
    static let coverCorner = Radius.s
    /// A round button in a row, such as play from here.
    /// css: specimen.css .round | width
    static let roundButton: CGFloat = 32

    // MARK: Buttons and chips

    /// The gap above a row of capsule buttons.
    /// css: specimen.css .button-row | padding-top
    static let buttonRowTop = Space.m.points
    /// css: specimen.css .button-row | gap
    static let buttonRowGap = Space.m.points
    /// css: specimen.css .capsule | min-height
    static let capsuleHeight = Measure.hitTarget
    /// css: specimen.css .capsule | gap
    static let capsuleGap = Space.s.points
    /// css: specimen.css .capsule | padding-left
    static let capsuleInset = Space.l.points
    /// A filter chip is lower than a capsule, so the chips read as a filter, not as buttons of the page.
    /// css: specimen.css .chip | min-height
    static let chipHeight: CGFloat = 30
    /// css: specimen.css .chip | padding-left
    static let chipPadding = Space.m.points
    /// css: person.html .chips | column-gap
    static let chipGap = Space.xs.points
    /// The gap above the chips.
    /// css: person.html .chips | padding-top
    static let chipsTop = Space.m.points
    /// The gap above the Works and About control.
    /// css: person.html .segmented | margin-top
    static let segmentedTop = Space.l.points

    /// The inset of the thumb in the Works and About control.
    /// css: person.html .segmented | padding-top
    static let segmentedPadding: CGFloat = 2
    /// css: person.html .segmented | border-top-left-radius
    static let segmentedCorner = Radius.m
    /// css: person.html .segmented button | min-height
    static let segmentedHeight: CGFloat = 32
    /// The soft shadow under the thumb.
    /// css: person.html .segmented button.on | box-shadow | 3px
    static let segmentedShadow: CGFloat = 3
    /// css: person.html .segmented button.on | box-shadow | 1px
    static let segmentedShadowY: CGFloat = 1
    /// The label of a tab in the Works and About control.
    /// css: person.html "segmented t-subheadline" | class
    static let segmentedLabel = TypeStyle.subheadline

    // MARK: Person page

    /// The gap under the name and its line, at the foot of the picture or under the back arrow.
    /// css: picture.css :root[data-page="person"] .hero .person-head | padding-bottom
    static let personHeadBottom = Space.m.points
    /// The gap from the picture to the first block under it. A page without a picture has none.
    /// css: picture.css :root[data-page="person"] .has-pic .hero + * | margin-top
    static let pictureBottom = Space.l.points
    /// The picture height as a share of the screen width.
    /// css: person.html .pic | height | 118vw
    static let pictureRatio: CGFloat = 1.18
    /// css: person.html .pic | height | 470px
    static let pictureMaxHeight: CGFloat = 470
    /// The fade over the picture reaches this far above the name block.
    /// css: person.html .hero | --fade | 96px
    static let pictureFade: CGFloat = 96
    /// The least picture height above the fade.
    /// css: person.html .pic | height | 220px
    static let pictureAboveFade: CGFloat = 220
    /// The blur under the name reaches this far above the name block.
    /// css: picture.css :root[data-page="person"] .hero .pic .blur | height | 72px
    static let pictureBlurAbove: CGFloat = 72
    /// The scrim under the name fades out this far above the name block.
    /// css: picture.css :root[data-page="person"] .hero .pic::after | height | 72px
    static let pictureScrimAbove: CGFloat = 72
    /// Blur and scrim stay full for `space-l` beside the longest text line, then fade out over this width.
    /// css: picture.css :root[data-page="person"] .hero .pic | --side-mask | 64px
    static let pictureSideFade: CGFloat = 64
    /// The column gap of the album grid.
    /// css: person.html .albums | column-gap
    static let albumColumnGap = Space.m.points
    /// The row gap of the album grid.
    /// css: person.html .albums | row-gap
    static let albumRowGap = Space.l.points
    /// css: person.html .albums img | border-top-left-radius
    static let albumCorner = Radius.m
    /// The gap from an album cover to its title. The year follows the title with no gap.
    /// css: person.html "margin-top: var(--space-xs)" | margin-top
    static let albumTitleGap = Space.xs.points

    // MARK: Player page

    /// The gap between the header lines of the player.
    /// css: player.html .hero | row-gap
    static let heroGap = Space.xs.points
    /// The gap under the large cover.
    /// css: player.html .hero .big | margin-bottom
    static let bigCoverBottom = Space.m.points
    /// css: player.html .hero .big | width
    static let bigCover = Measure.coverPage
    /// css: player.html .hero .big | border-top-left-radius
    static let bigCoverCorner = Radius.l
    /// The gap between the parts of an open movement row.
    /// css: player.html .open-body | row-gap
    static let openGap = Space.s.points
    /// The gap from the playback bar to its times.
    /// css: player.html .bar-box | row-gap
    static let barGap = Space.xs.points
    /// The playback bar of the playing movement. It has no handle.
    /// css: player.html .mv-bar | height
    static let positionBar: CGFloat = 6
    /// How far the touch area of the playback bar reaches above and below it, as a CSS inset: 44 points in all.
    /// css: player.html .mv-bar::after | top
    static let positionBarInset: CGFloat = -19
    /// The height of the player wash. It keeps its colour to `washSolid`, then fades into the page ground.
    /// css: player.html .wash | height
    static let washHeight: CGFloat = 640
    /// The share of the wash height that keeps the full wash colour.
    /// css: player.html .wash | background | 30%
    static let washSolid: CGFloat = 0.3
    /// The rise when an item ends: the old content leaves this far upwards.
    /// css: player.html .rise-out | transform | 40px
    static let riseOut: CGFloat = 40
    /// The rise when an item ends: the next content comes from this far below.
    /// css: player.html "transform: translateY(120px);" | transform | 120px
    static let riseIn: CGFloat = 120
    /// The handle at the top of the player overlay.
    /// css: overlay.css .player-overlay .grab::after | width
    static let grabberWidth: CGFloat = 36
    /// css: overlay.css .player-overlay .grab::after | height
    static let grabberHeight: CGFloat = 5

    // MARK: Mini player and timeline

    /// The play button and the cover of the mini player.
    /// css: pill.css .edge-pill > * | width
    static let pillItem: CGFloat = 48
    /// css: pill.css .edge-pill | column-gap
    static let pillGap = Space.xs.points
    /// css: pill.css .edge-pill | padding-top
    static let pillPadding = Space.xs.points
    /// css: pill.css .edge-pill .cover | border-top-left-radius
    static let pillCoverCorner = Radius.s
    /// The finger clearance between the scrub label and the screen edge.
    /// css: specimen.css .scrub-label | right
    static let scrubLabelEdge = Measure.hitTarget + Space.xs.points + 36
    /// The widest scrub label, as a share of the screen width.
    /// css: specimen.css .scrub-label | max-width | 70vw
    static let scrubLabelWidth: CGFloat = 0.7
    /// css: specimen.css .scrub-label | padding-top
    static let scrubLabelVertical = Space.xs.points
    /// css: specimen.css .scrub-label | padding-left
    static let scrubLabelHorizontal = Space.s.points
    /// css: specimen.css .scrub-label | border-top-left-radius
    static let scrubLabelCorner = Radius.s

    // MARK: Chronology

    /// The gap above the name of the composer in focus.
    /// css: chronology.html .chrono-head | padding-top
    static let chronologyHeadTop = Space.xs.points
    /// The heading keeps its height when the name and the line change, so the chart does not jump.
    /// css: chronology.html .chrono-head | min-height
    static let chronologyHeadHeight: CGFloat = 64
    /// The chart stays clear of the timeline on its side.
    /// css: chronology.html .chart | right
    static let chartTimelineGap = Measure.timeline + Space.s.points
    /// css: chronology.html .band-label | left
    static let bandLabelLeading = Space.l.points
    /// The column of decade years at the leading edge of the chart.
    /// css: chronology.html .tick | width
    static let tickWidth: CGFloat = 36
    /// A plain line: a contemporary, or a composer in the overview.
    /// css: chronology.html .line | width
    static let line: CGFloat = 2
    /// The focus composer and the composer last opened.
    /// css: chronology.html .line.focus | width
    static let lineMarked: CGFloat = 4
    /// The composer of what plays.
    /// css: chronology.html .line.playing | width
    static let linePlaying: CGFloat = 4
    /// The line under the finger of a scrub.
    /// css: chronology.html .line.picked | width
    static let linePicked: CGFloat = 6
    /// A line before the work period start.
    /// css: chronology.html .line.dim | opacity
    static let lineDim: CGFloat = 0.35
    /// A work of a contemporary.
    /// css: chronology.html .dot | width
    static let dot: CGFloat = 5
    /// A work of the focus composer.
    /// css: chronology.html .dot.focus | width
    static let dotFocus: CGFloat = 9
    /// The ring of page colour that sets a focus dot off its line.
    /// css: chronology.html .dot.focus | box-shadow | 2px
    static let dotFocusRing: CGFloat = 2
    /// The work that plays.
    /// css: chronology.html .dot.marked | width
    static let dotMarked: CGFloat = 15
    /// css: chronology.html .dot.marked | box-shadow | 4px
    static let dotMarkedRing: CGFloat = 4
    /// css: chronology.html .wrow | gap
    static let workRowGap = Space.s.points
    /// css: chronology.html .wrow | padding-left
    static let workRowPadding = Space.xs.points
    /// css: chronology.html .wrow | border-top-left-radius
    static let workRowCorner = Radius.s
    /// css: chronology.html .pick-label | padding-top
    static let pickLabelVertical = Space.xs.points
    /// The label clears the finger during a scrub.
    /// css: chronology.html .pick-label | --pick-above
    static let pickLabelAbove: CGFloat = 64
    /// css: chronology.html .pick-label | padding-left
    static let pickLabelHorizontal = Space.s.points
    /// css: chronology.html .pick-label | border-top-left-radius
    static let pickLabelCorner = Radius.s
    /// css: chronology.html .pick-label | box-shadow | 10px
    static let pickLabelShadow: CGFloat = 10
    /// css: chronology.html .pick-label | box-shadow | 2px
    static let pickLabelShadowY: CGFloat = 2
    /// css: chronology.html .pick-label | box-shadow | 0.18
    static let pickLabelShadowOpacity: CGFloat = 0.18
    /// The life, the count of works and the work period start.
    /// css: chronology.html "t-subheadline secondary" | class
    static let chronologyLine = TypeStyle.subheadline
    /// The decade years and the period names.
    /// css: chronology.html "tick t-caption2 nums" | class
    static let chronologyYear = TypeStyle.caption2
    /// A row of works, and the scrub label.
    /// css: chronology.html "wrow t-footnote" | class
    static let workRow = TypeStyle.footnote

    // MARK: Local Storage

    /// The height of the bar of the stores.
    /// css: specimen.css .storage-bar | height
    static let storageBar = Space.m.points
    /// The gap between two stores in the bar.
    /// css: specimen.css .storage-bar | gap
    static let storageBarGap = Space.xxs.points
    /// css: specimen.css .storage-bar | border-top-left-radius
    static let storageBarCorner = Radius.xs
    /// The narrowest store in the bar, so that a small store still shows.
    /// css: specimen.css .storage-bar > span | min-width
    static let storageBarMinimum = Space.xxs.points
    /// The colour dot of a store in the list under the bar.
    /// css: specimen.css .storage-dot | width
    static let storageDot = Space.s.points

    // MARK: Text

    /// The page title and the name on a person page.
    /// css: specimen.css h1[class] | font
    static let pageTitle = TypeStyle.pageTitle
    /// A section heading of a content page.
    /// css: specimen.css .section-head | font
    static let sectionHeading = TypeStyle.sectionHeading
    /// The meta line under a page title and the lines of a recording row.
    /// css: work.html "meta t-subheadline" | class
    static let metaLine = TypeStyle.subheadline
    /// A section footnote.
    /// css: work.html "section-foot t-footnote" | class
    static let footnote = TypeStyle.footnote
    /// The label of a capsule button.
    /// css: work.html "capsule filled t-headline" | class
    static let capsuleLabel = TypeStyle.headline
    /// The label of a filter chip.
    /// css: person.html "chip t-subheadline" | class
    static let chipLabel = TypeStyle.subheadline
    /// The favourite mark, in em of the text it follows.
    /// css: specimen.css .fermata | height | 0.64em
    static let fermataHeight: CGFloat = 0.64
    /// css: specimen.css .fermata | width | 1.036em
    static let fermataWidth: CGFloat = 1.036
    /// The gap from a name to the favourite mark after it, in em.
    /// css: specimen.css .fermata | margin-left | 0.25em
    static let fermataGap: CGFloat = 0.25
    /// The tracking of a role label, in em.
    /// css: specimen.css .role .label | letter-spacing | 0.06em
    static let roleLabelTracking: CGFloat = 0.06
}
