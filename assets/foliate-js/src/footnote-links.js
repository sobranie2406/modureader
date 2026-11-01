// Some converted EPUBs make both ends of a note link point to themselves.
// Repair only a verified pair; changing attributes preserves text nodes and CFIs.
export function repairSelfReferentialNotes(doc) {
    const sources = doc.querySelectorAll('a[id][href]')
    if (![...sources].some(a => /_note_\d+$/.test(a.id))) return
    const ids = new Map()
    for (const el of doc.querySelectorAll('[id]'))
        ids.set(el.id, ids.has(el.id) ? null : el)
    const links = new Map()
    for (const a of doc.querySelectorAll('a[href]')) {
        const href = a.getAttribute('href')
        if (!links.has(href)) links.set(href, [])
        links.get(href).push(a)
    }
    const marker = a => /^[\s\[\]［］*＊†‡§¶\d０-９]+$/u.test(a.textContent)
    for (const source of sources) {
        const match = /^(.*)_note_(\d+)$/.exec(source.id)
        if (!match || ids.get(source.id) !== source
            || source.getAttribute('href') !== `#${source.id}`) continue
        const noteID = `${match[1]}_noteBack_${match[2]}`
        const note = ids.get(noteID)
        if (!note || note.contains(source) || source.contains(note)
            || !/[^\s\[\]［］*＊†‡§¶\d０-９]/u.test(note.textContent)) continue
        const refs = links.get(`#${source.id}`) ?? []
        const backs = links.get(`#${noteID}`) ?? []
        if (!refs.length || !backs.length || !refs.every(marker)
            || !backs.every(a => note.contains(a) && marker(a))) continue
        for (const a of refs) a.setAttribute('href', `#${noteID}`)
        for (const a of backs) a.setAttribute('href', `#${source.id}`)
    }
}
