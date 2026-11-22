package util

class SqlPlotResult {
    /** Add named fields to a single sqlplot-tools RESULT record. */
    static String withFields(String record, Map fields) {
        def lines = record.readLines()
        if (lines.size() != 1 || !(lines[0] ==~ /RESULT[ \t].+/)) {
            throw new IllegalArgumentException('Expected one RESULT record')
        }

        String line = lines[0]
        // sqlplot-tools uses tabs as separators whenever the record contains a tab.
        def tokens = line.substring(7).tokenize(line.contains('\t') ? '\t' : ' ')
        def keys = tokens.collect { it.split('=', 2)[0].toLowerCase(Locale.ROOT) } as Set
        fields.each { key, value ->
            if (!(key ==~ /[A-Za-z_][A-Za-z0-9_]*/) || !keys.add(key.toLowerCase(Locale.ROOT))) {
                throw new IllegalArgumentException("Invalid or conflicting RESULT field: ${key}")
            }
            if (value == null || value.toString().find(/[\t\r\n]/)) {
                throw new IllegalArgumentException("Invalid value for RESULT field: ${key}")
            }
            tokens << "${key}=${value}"
        }
        return 'RESULT\t' + tokens.join('\t')
    }
}
