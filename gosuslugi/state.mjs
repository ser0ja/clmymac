'use strict';

import { readFile, writeFile } from 'node:fs/promises'

import { STATE_FILE } from './constants.mjs'

export const readState = async () => {
  try {
    return JSON.parse(await readFile(STATE_FILE, 'utf8'))
  } catch (error) {
    if (error.code !== 'ENOENT') console.error(`[state] не читается ${STATE_FILE}: ${error.message}`)
    return null
  }
}

export const writeState = async (snapshot) => {
  try {
    await writeFile(STATE_FILE, JSON.stringify({ snapshot, savedAt: new Date().toISOString() }, null, 2))
  } catch (error) {
    console.error(`[state] не сохраняется ${STATE_FILE}: ${error.message}`)
  }
}
