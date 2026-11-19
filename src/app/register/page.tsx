import RegisterForm from "./register-form";

type PageProps = {
  searchParams: Promise<{ ref?: string | string[] }>;
};

export default async function RegisterPage({ searchParams }: PageProps) {
  const params = await searchParams;
  const referral = Array.isArray(params.ref) ? params.ref[0] : params.ref ?? "";
  return <RegisterForm initialReferralCode={referral} />;
}
