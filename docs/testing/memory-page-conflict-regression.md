# Memory page conflict regression

Test: `MemoryPageEditorUITests.testConflictingSaveKeepsEditorDraft`.

## Controlled baseline

The production editor's Save action was temporarily restored to its previous unconditional `library.writePage` followed by dismissal. The explicit competing write fixture and the complete-draft assertions were retained. The fixed source was restored after the run.

On iPhone 18 Pro Test, iOS 27.3, the test failed because the expected Memory Page Changed alert did not exist after Save. The old save dismissed the editor instead of preserving the conflict for the owner. This is a controlled before/after comparison of the save behavior, not a claim that the exact historical revision contained the new fixture.

## Fixed result

On the same simulator, the actual test passed (1 executed, 0 failures). It captures the entire editor value before Save, waits until the newer stored value is visible, saves, dismisses the conflict alert, compares the complete draft for equality and verifies the newer stored value is unchanged.

Physical-device results are recorded separately in the pull request. This document contains no private memory contents or device/account identifiers.
