// Run from the repository root with nextflow run tests/managed_flags.nf
workflow {
    def command = new util.CommandBuilder('tool')
        .addFlag('--output', 'file')
        .addFlagIf(false, '--optional-file', null)
        .addOptions([seed: 7])
    assert command.build() == "'tool' '--output' 'file' '--seed' '7'"
    ['output', 'optional_file'].each { name ->
        def rejected = false
        try {
            command.addOptions([(name): 'override'])
        } catch (AssertionError error) {
            rejected = error.message.contains("Process manages option: ${name}")
        }
        assert rejected
    }
}
