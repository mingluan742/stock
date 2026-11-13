/**
 * 统一结果对象：所有业务方法都返回 Result，避免到处 try-catch
 * 用法：
 *   Result.success(data)
 *   Result.fail<Type>('余额不足')
 */
export class Result<T> {
  readonly ok: boolean;
  readonly data: T | null;
  readonly message: string;

  private constructor(ok: boolean, data: T | null, message: string) {
    this.ok = ok;
    this.data = data;
    this.message = message;
  }

  static success<T>(data: T): Result<T> {
    return new Result<T>(true, data, '');
  }

  static fail<T>(message: string): Result<T> {
    return new Result<T>(false, null, message);
  }
}