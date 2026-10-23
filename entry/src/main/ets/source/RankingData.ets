import { Comic } from '../model/Comic';
import { Res } from '../model/Res';

/** Fixed upstream parser.dart 707-749: ranking.load wins over loadWithNext. */
export class RankingData {
  options: Map<string, string> = new Map<string, string>();
  /** JS metadata is read lazily, never evaluated as a label/expression. */
  optionsLoader?: () => Promise<Res<Map<string, string>>>;
  load?: (option: string, page: number) => Promise<Res<Comic[]>>;
  loadWithNext?: (option: string, next: string | null) => Promise<Res<Comic[]>>;
}
