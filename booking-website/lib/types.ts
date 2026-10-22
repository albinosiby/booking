export type Tariff = {
  days: number[];
  opens_at: string | null;
  closes_at: string | null;
  date_from: string | null;
  date_until: string | null;
  price_minor: number | null;
};
export type BookingOption = {
  id: string;
  name: string;
  kind: string;
  sport: string | null;
  format: string | null;
  minimum_duration: number | null;
  duration_step: number | null;
  default_duration: number;
  fixed_time: string | null;
  from_minor: number | null;
  tariffs: Tariff[];
};
export type Resource = {
  images: string[];
  id: string;
  name: string;
  capacity: number;
  ground_id: string | null;
  section_ids: string[];
  options: BookingOption[];
};
export type Business = {
  id: string;
  name: string;
  type: string;
  timezone: string;
  today: string;
  location_name: string;
  address: string;
  resources: Resource[];
};
export type Website = {
  slug: string;
  title: string;
  description: string;
  contact_phone: string;
  instructions: string;
  cancellation_policy: string;
  currency: string;
  status: string;
  is_preview: boolean;
  has_logo: boolean;
  hero_image: string | null;
  notice_minutes: number;
  advance_days: number;
  businesses: Business[];
};
export type Selection = {
  business_id: string;
  resource_id: string;
  option_id: string;
  date: string;
  time: string;
  duration_minutes: number;
  people: number;
};
export type Slot = {
  time: string;
  date?: string;
  duration_minutes?: number;
  available: boolean;
  status: string;
  total_minor: number;
  remaining_capacity?: number;
  end_options?: [number, string][];
};
export type Quote = {
  quote_token: string;
  starts_at: string;
  ends_at: string;
  local_start: string;
  local_end: string;
  timezone: string;
  space_name: string;
  option_name: string;
  total_minor: number;
  currency: string;
};
export type Confirmation = Quote & {
  reference: string;
  status: string;
  payment_status: string;
};
