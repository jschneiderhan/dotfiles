import { helper } from '@ember/component/helper';

const communityPropertyTypes = [
  'Condo',
  'Townhouse',
  
];

export function rentalPropertyType(params/*, hash*/) {
  return params;
}

export default helper(rentalPropertyType);
