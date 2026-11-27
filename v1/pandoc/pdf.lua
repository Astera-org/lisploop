-- Lua filter for the pandoc -> pdflatex documents (see Makefile).  Two jobs:
--
-- 1. Add header.tex (next to this file) to the LaTeX preamble.  It is appended
--    to the document's own `header-includes`; pandoc's -H flag would replace
--    them, which breaks documents such as architecture2.md that load tikz.
--
-- 2. Let long inline code wrap.  Inline code is typeset as an unbreakable
--    \texttt box, so long identifiers and paths (make-additive-residual-decoder,
--    milestones/corpus.lisp:722) overflow table cells and the right margin.
--    Split such code after a - / : _ that sits between two name characters
--    (so not after the colon of a keyword like :code), and after a . that
--    starts a name (frame.lisp, but not 7.5), and allow a line break there;
--    nothing is added to the visible text.  Headings are skipped so the PDF
--    bookmarks stay plain.

if not FORMAT:match('latex') then
  return {}
end

local function add_header(meta)
  local path = pandoc.path.join{pandoc.path.directory(PANDOC_SCRIPT_FILE), 'header.tex'}
  local file = assert(io.open(path))
  local header = pandoc.RawBlock('latex', file:read('a'))
  file:close()
  local includes = meta['header-includes']
  if includes == nil then
    includes = pandoc.List{}
  elseif pandoc.utils.type(includes) ~= 'List' then
    includes = pandoc.List{includes}
  end
  includes:insert(header)
  meta['header-includes'] = includes
  return meta
end

local MIN = 3 -- keep at least this many characters on each side of a break

local function pieces(text)
  local out, start = {}, 1
  for i = 2, #text - 1 do
    local before, here, after = text:sub(i - 1, i - 1), text:sub(i, i), text:sub(i + 1, i + 1)
    if before:match('%w')
       and (here:match('[-/:_]') and after:match('%w') or here == '.' and after:match('%a'))
       and i - start + 1 >= MIN and #text - i >= MIN then
      out[#out + 1] = text:sub(start, i)
      start = i + 1
    end
  end
  out[#out + 1] = text:sub(start)
  return out
end

local function break_code(el)
  local parts = pieces(el.text)
  if #parts == 1 then
    return nil
  end
  local out = {}
  for i, part in ipairs(parts) do
    if i > 1 then
      out[#out + 1] = pandoc.RawInline('latex', '\\allowbreak{}')
    end
    out[#out + 1] = pandoc.Code(part, el.attr)
  end
  return out
end

return {{
  traverse = 'topdown',
  Meta = add_header,
  Header = function(h) return h, false end,
  Code = break_code,
}}
