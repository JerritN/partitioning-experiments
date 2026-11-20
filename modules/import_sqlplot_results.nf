/**
 * Imports sqlplot-tools RESULT records into a SQLite database.  
 *
 * **Inputs**  
 * `records`: File containing one RESULT record per run.  
 * `table`: SQL table name, also used as the database filename.  
 * The `sqlplot-tools` executable with SQLite support must be available on `PATH`.  
 *
 * **Outputs**  
 * `database`: SQLite database (`<table>.sqlite`) containing the imported rows.  
 */
process IMPORT_SQLPLOT_RESULTS {
    input:
    path records, stageAs: 'input/records'
    val table

    output:
    path("${table}.sqlite"), emit: database

    script:
    assert table ==~ /[A-Za-z_][A-Za-z0-9_]*/ : 'Expected a SQL identifier for table'
    def database = "${table}.sqlite"
    def command = new CommandBuilder('sqlplot-tools')
        .add('import-data', '-D', "sqlite:${database}", table, records)

    return new ScriptBuilder()
        .addLine("touch ${database}")
        .addCommand(command)
        .build()
}
