function terms = apcFeatures(z, method)
%APCFEATURES Fixed-order polynomial terms for training and deployment.
terms = [ones(size(z,1),1), z];
if strcmp(method,'quadratic')
    terms = [terms, z.^2];
    for first = 1:size(z,2)-1
        for second = first+1:size(z,2)
            terms(:,end+1) = z(:,first).*z(:,second); %#ok<AGROW>
        end
    end
elseif ~ismember(method,{'linear','ridge'})
    error('APC:ModelMethod','Unknown polynomial method: %s',method);
end
end
