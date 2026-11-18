#import <XCTest/XCTest.h>
#import "DuoDisplayMatch.h"

@interface DuoDisplayMatchTests : XCTestCase
@end

@implementation DuoDisplayMatchTests

- (void)testInnerPanelMatchesItsRenderGridInEitherOrientation {
    CGSize grid = CGSizeMake(2007, 2853);
    XCTAssertTrue(PKDuoMatchesRenderSize(grid, CGSizeMake(669, 951), 3));
    XCTAssertTrue(PKDuoMatchesRenderSize(grid, CGSizeMake(951, 669), 3));
    XCTAssertFalse(PKDuoMatchesRenderSize(CGSizeMake(1398, 2034), CGSizeMake(951, 669), 3));
}

- (void)testRenderGridRequiresTheSameScaleOnBothAxes {
    CGSize logical = CGSizeMake(669, 951);
    XCTAssertFalse(PKDuoMatchesRenderSize(CGSizeMake(669 * 2, 951 * 3), logical, 3));
    XCTAssertFalse(PKDuoMatchesRenderSize(CGSizeZero, logical, 3));
}

- (void)testInnerLandscapeScreenshotUsesTheOrientedPixelDimensions {
    CGSize landscape = CGSizeMake(951, 669);
    CGSize grid = CGSizeMake(2007, 2853);
    // On hardware, the upright JPEG was one pixel smaller per axis than XCTest's grid.
    XCTAssertTrue(PKDuoFrameMatchesGrid(CGSizeMake(2852, 2006), landscape, grid, 3));
    XCTAssertFalse(PKDuoFrameMatchesGrid(CGSizeMake(2006, 2852), landscape, grid, 3));
    // An inactive cover's image fit the old aspect-ratio check.
    XCTAssertFalse(PKDuoFrameMatchesGrid(CGSizeMake(2034, 1398), landscape, grid, 3));
}

- (void)testPortraitFramesOnBothPanels {
    CGSize inner = CGSizeMake(669, 951);
    CGSize cover = CGSizeMake(466, 678);
    XCTAssertTrue(PKDuoFrameMatchesGrid(CGSizeMake(2006, 2852), inner, CGSizeMake(2007, 2853), 3));
    XCTAssertTrue(PKDuoFrameMatchesGrid(CGSizeMake(1398, 2034), cover, CGSizeMake(1398, 2034), 3));
    XCTAssertFalse(PKDuoFrameMatchesGrid(CGSizeMake(2006, 2852), cover, CGSizeMake(1398, 2034), 3));
}

- (void)testXCTestBoundsGivenInPointsStillRequireRenderedPixels {
    CGSize landscape = CGSizeMake(951, 669);
    CGSize points = CGSizeMake(669, 951);
    XCTAssertTrue(PKDuoFrameMatchesGrid(CGSizeMake(2852, 2006), landscape, points, 3));
    XCTAssertFalse(PKDuoFrameMatchesGrid(landscape, landscape, points, 3));
}

- (void)testScreenshotMustAgreeWithBothTheSelectedPanelAndTheActiveWindow {
    CGSize landscape = CGSizeMake(951, 669);
    CGSize innerImage = CGSizeMake(2852, 2006);
    CGSize coverGrid = CGSizeMake(1398, 2034);
    XCTAssertFalse(PKDuoFrameMatchesGrid(innerImage, landscape, coverGrid, 3));
    XCTAssertFalse(PKDuoFrameMatchesGrid(CGSizeMake(2034, 1398), landscape, coverGrid, 3));
}

@end
