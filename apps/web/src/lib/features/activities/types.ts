export type ChoiceOption = {
	id: string;
	text: string;
};

export type QuestionDraft = {
	prompt: string;
	options: ChoiceOption[];
	correct_option_id: string;
	points: number;
	time_limit_seconds: number;
};

export type PlayQuestion = {
	id: string;
	prompt: string;
	points: number;
	time_limit_seconds: number;
	speed_scoring: boolean;
	options: ChoiceOption[];
};

export type PlayActivity = {
	id: string;
	title: string;
	share_code: string;
	cover_image_url: string | null;
	questions: PlayQuestion[];
};

export type QuestionResult = {
	question_id: string;
	prompt: string;
	selected_option_id: string | null;
	correct_option_id: string;
	timed_out: boolean;
	points_awarded: number;
	base_points: number;
	points_possible: number;
	speed_bonus: number;
	response_time_ms: number | null;
	correct: boolean;
};

export type AttemptResult = {
	id: string;
	learner_name: string;
	score: number;
	max_score: number;
	total_response_time_ms: number;
	results: QuestionResult[];
};

export type LeaderboardEntry = {
	rank: number;
	learner_name: string;
	score: number;
	max_score: number | null;
	response_time_ms: number;
};

export type PlayLeaderboard = {
	status: 'provisional';
	participant_count: number;
	podium: LeaderboardEntry[];
	standings: LeaderboardEntry[];
};

export type GameRoom = {
	room_code: string;
	title: string;
	status: 'waiting' | 'active' | 'completed';
	question_index: number;
	question_count: number;
	current_question: PlayQuestion | null;
	question_started_at: string | null;
	time_remaining_seconds: number;
	server_time: string;
	participant_count: number;
	answered_count: number;
	participants: Array<{ learner_name: string; completed: boolean }>;
	participant: { learner_name: string; answered: boolean } | null;
	standings: LeaderboardEntry[];
	podium: LeaderboardEntry[];
	standings_final: boolean;
};

export type PlaySession = {
	id: string;
	question_index: number;
	time_limit_seconds: number;
	time_remaining_seconds: number;
	question_started_at: string;
	server_time: string;
};

export type PlaySessionProgress =
	| {
			complete: false;
			is_correct: boolean;
			timed_out: boolean;
			points_awarded: number;
			speed_bonus: number;
			question_index: number;
			time_limit_seconds: number;
			question_started_at: string;
			server_time: string;
	  }
	| {
			complete: true;
			is_correct: boolean;
			timed_out: boolean;
			points_awarded: number;
			speed_bonus: number;
			attempt: AttemptResult;
	  };

export type PublishedActivity = {
	activity_id: string;
	title: string;
	version: number;
	share_code: string;
	play_path: string;
};

export type ResolvedJoinCode = { kind: 'live_room' | 'self_paced'; path: string };
export type JoinedGameRoom = { session_id: string; learner_name: string; room: GameRoom };
