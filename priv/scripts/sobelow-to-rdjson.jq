{
  source: {
    name: "sobelow",
    url: "https://github.com/nccgroup/sobelow"
  },
  diagnostics: (.findings.high_confidence + .findings.medium_confidence + .findings.low_confidence) | map({
    message: .type,
    code: {
      value: ((.type | split(": ")[0]) // "default"),
      url: null
    },
    location: {
      path: .file,
      range: {
        start: {
          line: .line,
          column: (.column // null)
        }
      }
    },
    severity: null
  })
}
