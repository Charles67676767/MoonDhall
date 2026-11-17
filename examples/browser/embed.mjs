const defaultModule = new URL(
  '../../_build/wasm-gc/release/build/examples/browser/browser.wasm',
  import.meta.url,
);

export async function loadPreview(input = defaultModule) {
  const bytes = input instanceof ArrayBuffer || ArrayBuffer.isView(input)
    ? input
    : await fetch(input).then(response => {
      if (!response.ok) throw new Error(`Could not load MoonDhall: HTTP ${response.status}`);
      return response.arrayBuffer();
    });
  const { instance } = await WebAssembly.instantiate(bytes, {}, {
    builtins: ['js-string'],
    importedStringConstants: '_',
  });
  return source => JSON.parse(instance.exports.preview(source));
}
