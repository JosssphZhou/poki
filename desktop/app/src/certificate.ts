export type CertificateToReplace = {
  name: string;
  serial: string;
  machine: string | null;
  days_left: number | null;
};

export function certificateWarning(certificate: CertificateToReplace, t: (key: string) => string): string {
  const { name, serial, machine, days_left } = certificate;
  const fill = (key: string, values: Record<string, string>) => t(key).replace(/\{(\w+)\}/g, (_, token: string) => values[token]);
  const identity = fill(
    machine ? "The certificate “{name}” (serial {serial}) was made by “{machine}”." : "The certificate is “{name}” (serial {serial}).",
    { name, serial, machine: machine ?? "" },
  );
  const expiry = days_left == null ? t("Its expiration date could not be read.")
    : days_left < 0 ? t("It has already expired.")
    : days_left === 0 ? t("It expires today.")
    : days_left === 1 ? t("It expires tomorrow.")
    : fill("It expires in {days} days.", { days: String(days_left) });
  return [
    t("Your Apple Account has reached its development certificate limit."), identity, expiry,
    t("Poki Setup on this computer cannot use the old certificate because its signing key is on the computer or in the app that created it."),
    t("Replacing it lets this computer sign Poki. Every app signed with the old certificate will stop opening on all affected iPhones and iPads until it is reinstalled with a valid certificate."),
    t("If another computer still signs Poki for you, use that computer instead."),
  ].join(" ");
}
