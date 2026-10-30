// 句子切分：只按空行分句；单个换行按空格处理；段内标点不再单独切
export function stripMarkdown(text: string): string {
  let t: string = text.replace(/\r/g, '');
  t = t.replace(/^---[ \t]*\n[\s\S]*?\n---[ \t]*\n/, '');
  t = t.replace(/```[\s\S]*?```/g, ' ');
  t = t.replace(/`([^`]+)`/g, '$1');
  t = t.replace(/!\[([^\]]*)\]\([^)]*\)/g, '$1');
  t = t.replace(/\[([^\]]+)\]\([^)]*\)/g, '$1');
  t = t.replace(/^#{1,6}\s*/gm, '');
  t = t.replace(/^\s*[-*+]\s+/gm, '');
  t = t.replace(/^\s*\d+\.\s+/gm, '');
  t = t.replace(/^\s*>\s?/gm, '');
  t = t.replace(/[*_~]{1,3}/g, '');
  t = t.replace(/<[^>]+>/g, ' ');
  return t;
}

export function splitSentences(text: string): string[] {
  const out: string[] = [];
  const normalized: string = text.replace(/\r/g, '');
  const blocks: string[] = normalized.split(/\n[ \t]*\n+/);
  blocks.forEach((block: string) => {
    const line: string = block.replace(/\n+/g, ' ').trim();
    if (line.length > 0) {
      out.push(line);
    }
  });
  return out;
}
