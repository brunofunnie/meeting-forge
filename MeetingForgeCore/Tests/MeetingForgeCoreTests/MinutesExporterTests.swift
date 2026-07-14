import Testing
@testable import MeetingForgeCore

@Test func htmlWrapsRenderedMarkdown() {
    let html = MinutesExporter.html(markdown: "# Ata\n\n- **ponto** um", title: "Reunião 14/07")
    #expect(html.contains("<h1>Ata</h1>"))
    #expect(html.contains("<strong>ponto</strong>"))
    #expect(html.contains("<title>Reunião 14/07</title>"))
    #expect(html.lowercased().contains("<!doctype html>"))
    #expect(html.contains("@media print")) // print-friendly CSS present
}

@Test func htmlEscapesTitle() {
    let html = MinutesExporter.html(markdown: "text", title: "<script>x</script>")
    #expect(!html.contains("<script>x</script>"))
}
