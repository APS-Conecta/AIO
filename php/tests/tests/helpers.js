// Shared login flow for the wizard's Playwright scenarios (the fork's es-CL suite, patch 090).
//
// ./setup renders the one-time passphrase page while the instance is not installed; we scrape
// the passphrase, open the login in the popup (the setup link keeps target="_blank"), and log
// in there — the containers page is the popup, the setup page stays behind it.

export async function logInToContainersPage(setupPage) {
  // Extract initial password
  await setupPage.goto('./setup');
  const password = await setupPage.locator('#initial-password').innerText()
  const containersPagePromise = setupPage.waitForEvent('popup');
  await setupPage.getByRole('link', { name: 'Abrir el inicio de sesión de Nextcloud AIO ↗' }).click();
  const containersPage = await containersPagePromise;

  // Log in and wait for redirect
  await containersPage.locator('#master-password').click();
  await containersPage.locator('#master-password').fill(password);
  await containersPage.getByRole('button', { name: 'Iniciar sesión' }).click();
  await containersPage.waitForURL('./containers');
  return containersPage;
}