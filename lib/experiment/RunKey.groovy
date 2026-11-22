package experiment

import groovy.transform.EqualsAndHashCode

@EqualsAndHashCode(includeFields = true)
final class RunKey implements Serializable {
    private final int stage
    private final Map choices

    RunKey(int stage, Map choices) {
        this.stage = stage
        this.choices = new LinkedHashMap(choices).asImmutable()
    }

    // Nextflow restores cached task contexts without the workflow class loader.
    Map toTaskKey() {
        [stage: stage, choices: new LinkedHashMap(choices)]
    }

    String toString() {
        "stage ${stage} ${choices}"
    }
}
