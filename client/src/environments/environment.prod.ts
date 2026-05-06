// TODO: Replace with your actual ALB DNS before production build
// Get ALB DNS from AWS Console → EC2 → Load Balancers → Your ALB → DNS name
export const environment = {
  production: true,
  apiUrl: 'http://your-alb-dns.us-east-1.elb.amazonaws.com/api/users'
};