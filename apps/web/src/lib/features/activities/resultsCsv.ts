import type { GameRoomReport } from './types';

function csvCell(value: string) {
	const spreadsheetSafeValue = /^[\s]*[=+\-@]/.test(value) ? `'${value}` : value;
	return `"${spreadsheetSafeValue.replaceAll('"', '""')}"`;
}

export function buildGameRoomResultsCsv(report: GameRoomReport) {
	const rows = [
		[
			'Learner',
			'Character',
			'Rank',
			'Final score',
			'Maximum score',
			'Question number',
			'Question',
			'Learner answer',
			'Correct answer',
			'Result',
			'Points awarded',
			'Points possible',
			'Response time (ms)'
		]
	];

	for (const participant of report.participants) {
		for (const question of report.questions) {
			const result = participant.questions.find((item) => item.question_id === question.id);
			if (!result) continue;
			rows.push([
				participant.learner_name,
				participant.avatar_id,
				String(participant.rank),
				String(participant.score),
				String(participant.max_score),
				String(question.number),
				question.prompt,
				result.selected_answer || (result.timed_out ? 'No answer' : ''),
				result.correct_answer,
				result.is_correct ? 'Correct' : result.timed_out ? 'Timed out' : 'Incorrect',
				String(result.points_awarded),
				String(result.points_possible),
				result.response_time_ms === null ? '' : String(result.response_time_ms)
			]);
		}
	}

	return `\uFEFF${rows.map((row) => row.map(csvCell).join(',')).join('\r\n')}`;
}
