import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { Script, createContext } from 'node:vm'

/**
 * Load a `.pragma library` QML/JS file and return its exported functions.
 *
 * QML library files use top-level `function foo() {}` declarations that become
 * properties of the import namespace. We replicate this by running the script
 * inside a V8 sandbox and collecting every function from the context.
 */
export function loadQmlLib(relPath) {
  const absPath = resolve(relPath)
  let code = readFileSync(absPath, 'utf-8')

  // Strip the `.pragma library` directive (not valid JS).
  code = code.replace(/^\.pragma\s+library\s*$/m, '')

  // Provide standard globals that QML JS code may reference.
  const sandbox = {
    console,
    Math,
    JSON,
    Date,
    Array,
    Object,
    String,
    Number,
    RegExp,
    parseInt,
    parseFloat,
    isNaN,
    isFinite,
    undefined,
    NaN,
    Infinity,
    encodeURIComponent,
    decodeURIComponent,
    encodeURI,
    decodeURI,
  }

  const ctx = createContext(sandbox)
  new Script(code, { filename: absPath }).runInContext(ctx)

  // Collect all functions from the sandbox (top-level declarations leak into context).
  const exports = {}
  for (const key of Object.keys(ctx)) {
    if (typeof ctx[key] === 'function') {
      exports[key] = ctx[key]
    }
  }

  return exports
}
