import groovy.transform.Canonical

@Canonical
class Experiment {
    final String name
    final List<PlannedStage> stages

    void verifyStageSequence(List expectedTools) {
        def actualTools = stages*.tool
        if (actualTools != expectedTools)
            throw new IllegalArgumentException("Expected stages ${expectedTools}; received ${actualTools}")
    }
}
