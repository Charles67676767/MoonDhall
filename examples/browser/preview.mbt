///|
/// Returns a JSON envelope. Keep the preview as text to preserve exact integers.
pub fn preview(source : String) -> String {
  try {
    let inferred = @dhall.check(source).display()
    let json = @dhall.to_json(source)
    Json::object({ "type": Json::string(inferred), "json": Json::string(json) }).stringify()
  } catch {
    error => {
      let message = @dhall.diagnostic(error, source, "editor.dhall")
      Json::object({ "error": Json::string(message) }).stringify()
    }
  }
}
