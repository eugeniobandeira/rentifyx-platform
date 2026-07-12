# Pull Request Template

## Description

Provide a brief summary of what this PR does and why.

## Type of Change

- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Refactor
- [ ] Other: _____________________

## Files Changed

List the main files and components affected by this PR.

- `prod/main.tf`
- `modules/`
- `.github/workflows/terraform.yml`
- `scripts/`

## How to Test

Describe how to validate this PR locally without creating AWS resources.

- Run `terraform fmt -check`
- Run `terraform validate`
- Confirm no sensitive files are included

## Additional Notes

Add any extra context, important decisions, or warnings.

## Checklist

- [ ] Code has been reviewed
- [ ] PR aligns with project goals
- [ ] No AWS resources were created/accessed without approval
- [ ] Relevant documentation was added/updated
