import Papa from 'papaparse';
import readXlsxFile from 'read-excel-file/browser';
import type { SheetData } from 'read-excel-file/browser';
import type { QuestionDraft } from './types';

const MAX_FILE_SIZE = 5 * 1024 * 1024;
const MAX_QUESTIONS = 100;
const OPTION_COLUMNS = ['option_a', 'option_b', 'option_c', 'option_d', 'option_e', 'option_f'];
const REQUIRED_COLUMNS = ['question', 'option_a', 'option_b', 'correct_answer'];

type ImportRow = Record<string, unknown>;

export async function importQuestionFile(file: File): Promise<QuestionDraft[]> {
	if (file.size === 0 || file.size > MAX_FILE_SIZE) {
		throw new Error('Choose a non-empty CSV or XLSX file no larger than 5 MB.');
	}

	let rows: ImportRow[];
	const extension = file.name.split('.').pop()?.toLowerCase();
	if (extension === 'csv') {
		rows = parseCsv(await file.text());
	} else if (extension === 'xlsx') {
		const sheets = await readXlsxFile(file);
		rows = rowsFromSheet(sheets[0]?.data ?? []);
	} else {
		throw new Error('Choose a CSV (.csv) or Excel workbook (.xlsx).');
	}

	if (rows.length === 0) throw new Error('The file has no question rows.');
	if (rows.length > MAX_QUESTIONS) {
		throw new Error(`Import no more than ${MAX_QUESTIONS} questions at a time.`);
	}

	return rows.map((row, index) => questionFromRow(row, index + 2));
}

function parseCsv(text: string): ImportRow[] {
	const parsed = Papa.parse<Record<string, string>>(text, {
		header: true,
		skipEmptyLines: 'greedy',
		transformHeader: (header: string) => header.trim().toLowerCase()
	});
	if (parsed.errors.length > 0) {
		const parseError = parsed.errors[0];
		if (!parseError) throw new Error('The CSV file could not be read.');
		throw new Error(`Could not read CSV row ${(parseError.row ?? 0) + 2}: ${parseError.message}`);
	}
	return parsed.data.map((row: Record<string, string>) => Object.fromEntries(Object.entries(row)));
}

function rowsFromSheet(sheet: SheetData): ImportRow[] {
	if (sheet.length === 0) return [];
	const headers = sheet[0].map((cell) =>
		String(cell ?? '')
			.trim()
			.toLowerCase()
	);
	return sheet
		.slice(1)
		.filter((cells) => cells.some((cell) => String(cell ?? '').trim() !== ''))
		.map((cells) =>
			Object.fromEntries(headers.map((header, index) => [header, cells[index] ?? '']))
		);
}

function questionFromRow(row: ImportRow, rowNumber: number): QuestionDraft {
	for (const column of REQUIRED_COLUMNS) {
		if (!String(row[column] ?? '').trim()) {
			throw new Error(`Row ${rowNumber}: “${column}” is required.`);
		}
	}

	const prompt = String(row.question).trim();
	if (prompt.length > 500)
		throw new Error(`Row ${rowNumber}: questions must be 500 characters or fewer.`);

	const optionValues = OPTION_COLUMNS.map((column) => String(row[column] ?? '').trim());
	const lastOptionIndex = optionValues.findLastIndex(Boolean);
	if (optionValues.slice(0, lastOptionIndex + 1).some((option) => !option)) {
		throw new Error(`Row ${rowNumber}: answer columns must be filled in order from option_a.`);
	}
	const options = optionValues.slice(0, lastOptionIndex + 1);
	if (options.length < 2 || options.length > 6 || options.some((option) => option.length > 160)) {
		throw new Error(`Row ${rowNumber}: provide 2–6 answers, each no longer than 160 characters.`);
	}

	const rawCorrect = String(row.correct_answer).trim();
	const correctIndex = /^[A-F]$/i.test(rawCorrect)
		? rawCorrect.toUpperCase().charCodeAt(0) - 65
		: options.findIndex((option) => option.toLowerCase() === rawCorrect.toLowerCase());
	if (correctIndex < 0 || correctIndex >= options.length) {
		throw new Error(
			`Row ${rowNumber}: correct_answer must be A–F or exactly match an answer choice.`
		);
	}

	const points = optionalInteger(row.points, 1, 1, 1000, rowNumber, 'points');
	const speedBonusPoints = optionalInteger(
		row.speed_bonus_points,
		100,
		0,
		100_000,
		rowNumber,
		'speed_bonus_points'
	);
	const timeLimit = optionalInteger(
		row.time_limit_seconds,
		30,
		5,
		300,
		rowNumber,
		'time_limit_seconds'
	);

	const choices = options.map((text) => ({ id: crypto.randomUUID(), text }));
	return {
		question_type: 'single_choice',
		prompt,
		options: choices,
		correct_option_id: choices[correctIndex].id,
		correct_option_ids: [choices[correctIndex].id],
		points,
		speed_bonus_points: speedBonusPoints,
		time_limit_seconds: timeLimit
	};
}

function optionalInteger(
	value: unknown,
	defaultValue: number,
	minimum: number,
	maximum: number,
	rowNumber: number,
	label: string
): number {
	if (value === undefined || value === null || String(value).trim() === '') return defaultValue;
	const number = Number(value);
	if (!Number.isInteger(number) || number < minimum || number > maximum) {
		throw new Error(`Row ${rowNumber}: ${label} must be an integer from ${minimum} to ${maximum}.`);
	}
	return number;
}
