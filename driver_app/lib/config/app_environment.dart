enum AppEnvironment {
  dev('DEV'),
  stg('STG'),
  prod('PROD');

  const AppEnvironment(this.label);

  final String label;
}
