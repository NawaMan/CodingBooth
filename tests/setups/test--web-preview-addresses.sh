#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
set -euo pipefail
source ../common--source.sh
if ! command -v node >/dev/null; then
  echo "SKIP: Web Preview address tests require Node."
  exit 0
fi
node <<'JS'
const assert = require('node:assert/strict');
const { parseTarget } = require('../../variants/base/setups/booth-web-preview/media/target');
for (const input of ['8080', ':8080', 'booth:8080', 'http://booth:8080/']) {
  assert.equal(parseTarget(input).address, 'http://booth:8080/');
}
const address = 'http://booth:8080/nested/a%20b?q=%2F&next=one#section';
assert.equal(parseTarget(address).address, address);
assert.equal(parseTarget('/next', 'http://booth:80/a').address, 'http://booth:80/next');
assert.equal(parseTarget('?new=1', address).address, 'http://booth:8080/nested/a%20b?new=1');
assert.equal(parseTarget('#other', address).address, address.replace('#section', '#other'));
for (const input of ['', '0', '65536', '10000', '10007', '19999', 'https://booth:8080', 'http://booth/', 'javascript:alert(1)', 'data:text/html,test', 'ftp://example.com/', 'http://booth:8080@evil.example/', '//evil.example/']) {
  assert.throws(() => parseTarget(input, 'http://booth:8080/'), undefined, input);
}
assert.equal(parseTarget('65535/').port, 65535);
for (const [input, expected] of [
  ['http://example.com/path?q=one#part', 'http://example.com/path?q=one#part'],
  ['example.com/path', 'https://example.com/path'],
  ['myserver:3000', 'https://myserver:3000/'],
  ['localhost:8080', 'http://localhost:8080/'],
  ['http://127.0.0.1:10000', 'http://127.0.0.1:10000/'],
  ['https://[::1]:8080/', 'https://[::1]:8080/'],
]) {
  const target = parseTarget(input);
  assert.equal(target.kind, 'external');
  assert.equal(target.port, null);
  assert.equal(target.url, expected);
}
assert.equal(parseTarget('/next', 'https://example.com/start').url, 'https://example.com/next');
for (const query of ['python', 'python async examples', 'site:python.org async', 'cats & dogs + café #1']) {
  const target = parseTarget(query);
  const url = new URL(target.url);
  assert.equal(target.kind, 'search');
  assert.equal(target.address, query);
  assert.equal(target.title, 'Search: ' + query);
  assert.equal(url.origin + url.pathname, 'https://www.google.com/search');
  assert.equal(url.searchParams.get('q'), query);
  assert.equal(url.searchParams.get('igu'), '1');
  assert.deepEqual(parseTarget(target.address), target, 'saved searches restore without losing their text');
}
console.log('PASS: booth ports, external addresses, bare hosts, relative navigation and encoded Google searches');
JS
print_test_result true "$0" 1 "Preview addresses select the intended booth server, external page or Google search"
