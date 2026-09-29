-- Pandoc filter adapting the Markdown documents for publishing as HTML pages.

-- Rewrite relative links to Markdown files (e.g. `SPEC.md#section`) so that
-- they point to the corresponding generated HTML page.
function Link(el)
  if el.target:match('^%a[%w+.-]*:') then
    return nil
  end
  local path, fragment = el.target:match('^([^#]*)(.*)$')
  if path:match('%.md$') then
    el.target = path:sub(1, -4) .. '.html' .. fragment
    return el
  end
end

local function warn(message)
  local source = PANDOC_STATE.input_files[1] or 'stdin'
  message = source .. ': ' .. message
  if pandoc.log then
    pandoc.log.warn(message)
  else
    io.stderr:write('[WARNING] ' .. message .. '\n')
  end
end

-- Return the generated HTML page of a sibling document linked from `block`.
local function linked_page(block)
  local page
  block:walk {
    Link = function(el)
      local path = el.target:match('^([^:#/]+)%.html$') or el.target:match('^([^:#/]+)%.md$')
      page = page or (path and path .. '.html')
    end,
  }
  return page
end

-- Anchor the entries of the `Normative references` section, which start with
-- a bold key (e.g. `**[RFC2119]**`). Return the set of their keys, and the
-- pages of the entries which refer to a sibling document by key.
local function anchor_references(doc)
  local keys, pages = {}, {}
  local in_refs = false
  for _, block in ipairs(doc.blocks) do
    if block.t == 'Header' then
      in_refs = pandoc.utils.stringify(block.content):lower() == 'normative references'
    elseif in_refs and block.t == 'BulletList' then
      for _, item in ipairs(block.content) do
        local first = item[1]
        local label = first and first.content and first.content[1]
        if label and label.t == 'Strong' then
          local key = pandoc.utils.stringify(label):match('^%[([%w.-]+)%]$')
          if key then
            keys[key] = true
            pages[key] = linked_page(first)
            first.content[1] = pandoc.Span(label, { id = 'ref-' .. key:lower() })
          end
        end
      end
    end
  end
  return keys, pages
end

-- Anchor the numbered headings (e.g. `6.7.1 Inheritance`) as `sec-6.7.1`, so
-- that other documents can link to them by number, and return the set of the
-- section numbers.
local function anchor_sections(doc)
  local sections = {}
  for _, block in ipairs(doc.blocks) do
    if block.t == 'Header' then
      local number = pandoc.utils.stringify(block.content):match('^(%d[%d.]*)%s')
      if number then
        number = number:gsub('%.+$', '')
        sections[number] = true
        block.content:insert(1, pandoc.Span({}, { id = 'sec-' .. number }))
      end
    end
  end
  return sections
end

-- Split `text` at the section numbers (e.g. `(§6.7.1).`), linking each one to
-- the target returned by `resolve`. Return nil if nothing was linked.
local function split_sections(text, resolve)
  local inlines = pandoc.Inlines {}
  local done, pos = 1, 1
  while true do
    local start, _, number = text:find('§(%d[%d.]*)', pos)
    if not start then
      break
    end
    number = number:gsub('%.+$', '')
    pos = start + #'§' + #number
    local target = resolve(number)
    if target then
      if start > done then
        inlines:insert(pandoc.Str(text:sub(done, start - 1)))
      end
      inlines:insert(pandoc.Link('§' .. number, target))
      done = pos
    end
  end
  if done == 1 then
    return nil
  end
  if done <= #text then
    inlines:insert(pandoc.Str(text:sub(done)))
  end
  return inlines
end

-- Link the section numbers (e.g. `§6.7.1`) to the numbered headings. A number
-- preceded by a reference (e.g. `[CSIL] §6`) is linked to the sibling document
-- of that reference, or not at all if the reference is not a sibling document.
local function link_sections(doc, sections, pages)
  local function resolver(inlines, i)
    local space, word = inlines[i - 1], inlines[i - 2]
    local key = space and space.t == 'Space' and word and word.t == 'Str'
      and word.text:match('%[([%w.-]+)%]$')
    if key then
      local page = pages[key]
      return function(number)
        return page and page .. '#sec-' .. number
      end
    end
    return function(number)
      if sections[number] then
        return '#sec-' .. number
      end
      warn('unresolved section reference §' .. number)
    end
  end

  return doc:walk {
    traverse = 'topdown',
    -- Leave existing links untouched.
    Link = function(el)
      return el, false
    end,
    Inlines = function(inlines)
      local result = pandoc.Inlines {}
      for i, el in ipairs(inlines) do
        local split = el.t == 'Str' and el.text:find('§', 1, true)
          and split_sections(el.text, resolver(inlines, i))
        if split then
          result:extend(split)
        else
          result:insert(el)
        end
      end
      return result
    end,
  }
end

-- Link the in-line references (e.g. `[RFC2119]`) to their entry in the
-- `Normative references` section.
local function link_references(doc, keys)
  return doc:walk {
    traverse = 'topdown',
    -- Leave the anchored entries and existing links untouched.
    Span = function(el)
      if el.identifier:match('^ref%-') then
        return el, false
      end
    end,
    Link = function(el)
      return el, false
    end,
    Str = function(el)
      local prefix, key, suffix = el.text:match('^([^%[]*)%[([%w.-]+)%](.*)$')
      if not keys[key] then
        return nil
      end
      local inlines = pandoc.Inlines {}
      if prefix ~= '' then
        inlines:insert(pandoc.Str(prefix))
      end
      inlines:insert(pandoc.Link('[' .. key .. ']', '#ref-' .. key:lower()))
      if suffix ~= '' then
        inlines:insert(pandoc.Str(suffix))
      end
      -- Do not descend into the new link, which would be replaced again.
      return inlines, false
    end,
  }
end

-- Use the first level-1 heading as the page title, unless the metadata
-- already provides one.
local function set_title(doc)
  if doc.meta.pagetitle or doc.meta.title then
    return
  end
  for _, block in ipairs(doc.blocks) do
    if block.t == 'Header' and block.level == 1 then
      doc.meta.pagetitle = pandoc.utils.stringify(block.content)
      return
    end
  end
end

function Pandoc(doc)
  local keys, pages = anchor_references(doc)
  local sections = anchor_sections(doc)
  doc = link_sections(doc, sections, pages)
  doc = link_references(doc, keys)
  set_title(doc)
  return doc
end
