package experiment

import groovy.transform.Canonical
import util.Assertions

@Canonical
class Experiment {
    final String name
    final List<PlannedStage> stages

    void verifyStageSequence(List expectedTools) {
        def actualTools = stages*.tool
        Assertions.assertThat(actualTools == expectedTools, "Expected stages ${expectedTools}; received ${actualTools}")
    }
}
