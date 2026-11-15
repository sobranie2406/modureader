if (input.actionId !== "import-policy") {
  throw new Error("Unknown private import action");
}
return {private: !!(input.settings && input.settings.auto_import === true)};
