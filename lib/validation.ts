export const defaultRules = { matchMeter: false, futureDate: false };
export function validateRecord(r: any, rules = defaultRules): string | null {
 if (!r || !/^[a-f0-9-]{36}$/i.test(r.id || '')) return 'Identificador inválido.';
 if (typeof r.fleet !== 'string' || !r.fleet.trim() || r.fleet.length > 60) return 'Selecione a frota.';
 if (typeof r.operator !== 'string' || r.operator.trim().length < 2 || r.operator.length > 120) return 'Informe o trabalhador.';
 if (!/^\d{4}-\d{2}-\d{2}$/.test(r.date || '') || new Date(r.date+'T12:00:00Z').toISOString().slice(0,10) !== r.date) return 'Data inválida.';
 const today = new Intl.DateTimeFormat('en-CA',{timeZone:'America/Sao_Paulo'}).format(new Date());
 if (!rules.futureDate && r.date > today) return 'A data não pode estar no futuro.';
 for (const k of ['start','end','liters']) if (typeof r[k] !== 'number' || !Number.isFinite(r[k]) || r[k] < 0 || r[k] > 1e9) return 'Preencha as leituras e os litros com números válidos.';
 if (r.liters <= 0) return 'Os litros devem ser maiores que zero.';
 if (r.end <= r.start) return 'O registro final deve ser maior que o inicial.';
 if (rules.matchMeter && Math.abs((r.end-r.start)-r.liters) > .02) return 'Os litros devem corresponder à diferença do medidor.';
 for (const k of ['engine','elevator','km']) if (typeof r[k] !== 'number' || !Number.isFinite(r[k]) || r[k] < 0 || r[k] > 1e9) return 'KM e os dois horímetros são obrigatórios e devem ser maiores ou iguais a zero.';
 if (typeof r.notes !== 'string' || r.notes.length > 1000) return 'Observação muito longa.';
 if (typeof r.createdAt !== 'string' || !Number.isFinite(Date.parse(r.createdAt))) return 'Horário de criação inválido.';
 return null;
}
