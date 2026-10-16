import type { PageLoad } from './$types';

export const load: PageLoad = ({ params }) => ({ activityId: params.id });
