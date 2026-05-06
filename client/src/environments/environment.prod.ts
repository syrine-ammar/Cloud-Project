// TODO: Replace with your actual ALB DNS before production build
// Get ALB DNS from AWS Console → EC2 → Load Balancers → Your ALB → DNS name
export const environment = {
  production: true,
  apiUrl: 'ALB_DNS_PLACEHOLDER/api/users'
};